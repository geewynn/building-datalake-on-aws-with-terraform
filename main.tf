data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name                 = "datalake-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_iam_role" "glueroles" {
  name = "admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "glue.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin_policy_attachment" {
  role       = aws_iam_role.glueroles.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_db_subnet_group" "datalake" {
  name       = "datalake-sg"
  subnet_ids = module.vpc.public_subnets

  tags = {
    Name = "Datalake"
  }
}

resource "aws_security_group" "rds" {
  name   = "datalake_rds"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "datalake_rds"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id = module.vpc.vpc_id
  service_name = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  # security_group_ids = [aws_security_group.rds.id]
  route_table_ids = module.vpc.public_route_table_ids
  
}
resource "aws_db_instance" "datalake" {
  identifier             = "datalake"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "mysql"
  engine_version         = "8.0"
  username               = var.db_user
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.datalake.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
}

resource "null_resource" "database_setup" {
  depends_on = [aws_db_instance.datalake]

  provisioner "local-exec" {
    command = "mysql --local-infile=1 -h ${aws_db_instance.datalake.address} -u ${aws_db_instance.datalake.username} --password=${aws_db_instance.datalake.password} < mysql/mysql_bootstrap.sql"
  }
}


resource "aws_glue_catalog_database" "aws_dl_db" {
  depends_on = [ aws_db_instance.datalake ]
  name = "tickit_glue_db"
}


resource "aws_glue_connection" "tickit_glue_connection" {
  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:mysql://${aws_db_instance.datalake.endpoint}/tickit"
    PASSWORD            = var.db_password
    USERNAME            = var.db_user
  }

  name = "tickit_glue_connection"

  physical_connection_requirements {
    availability_zone      = data.aws_availability_zones.available.names[0] #data.aws_availability_zones.available
    security_group_id_list = [aws_security_group.rds.id] #[aws_security_group.example.id]
    subnet_id              = module.vpc.public_subnets[0] # aws_subnet.example.id
  }
}


resource "aws_glue_crawler" "tickit_glue_crawler" {
  database_name = aws_glue_catalog_database.aws_dl_db.name
  name          = "tickit_mysql_crawlers"
  role          = aws_iam_role.glueroles.arn

  depends_on = [ aws_glue_connection.tickit_glue_connection ]

  jdbc_target {
    connection_name = aws_glue_connection.tickit_glue_connection.name
    path            = "tickit/%"
  }
}

resource "null_resource" "aws_glue_crawler_run" {
  depends_on = [aws_glue_crawler.tickit_glue_crawler]

  provisioner "local-exec" {
    command = "aws glue start-crawler --name ${aws_glue_crawler.tickit_glue_crawler.name}"
  }
}


resource "aws_glue_job" "job1" {
  name        = "tickit_listing_raw_job"
  role_arn    = aws_iam_role.glueroles.arn
  worker_type = "Standard"
  number_of_workers = 1
  command {
    name            = "tickit_listing_raw"
    script_location = ""
    python_version  = "3.9"
  }
  default_arguments = {
    "--TempDir" = ""
  }
}

resource "aws_glue_job" "job2" {
  name        = "tickit_listing_refined_job"
  role_arn    = aws_iam_role.glueroles.arn
  worker_type = "Standard"
  number_of_workers = 1
  command {
    name            = "tickit_listing_refined"
    script_location = ""
    python_version  = "3.9"
  }
  default_arguments = {
    "--TempDir" = ""
  }
}


resource "aws_glue_trigger" "trigger_job2" {
  name     = "trigger-job2"
  type     = "CONDITIONAL"
  actions {
    job_name = aws_glue_job.job2.name
  }
  predicate {
    conditions {
      job_name    = aws_glue_job.job1.name
      state       = "SUCCEEDED"
      logical_operator = "EQUALS"
    }
  }
}