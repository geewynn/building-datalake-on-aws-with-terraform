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

# resource "aws_iam_role" "gluerole" {
#   name = "gluerole"

#   # Terraform's "jsonencode" function converts a
#   # Terraform expression result to valid JSON syntax.
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Action": "*",
#             "Resource": "*"
#         }
#     ]
#   })
# }

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
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "datalake_rds"
  }
}

resource "aws_db_instance" "datalake" {
  identifier             = "datalake"
  # db_name                = "tickit"
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



# resource "null_resource" "database_setup" {
#   depends_on = [aws_db_instance.datalake]

#   provisioner "local-exec" {

#     command = <<EOT
#         "mysql -h ${aws_db_instance.datalake.endpoint} -u ${aws_db_instance.datalake.username} -p${aws_db_instance.datalake.password} ${aws_db_instance.datalake.db_name} < C:\\Users\\ekain\\Documents\\aws-datalake\\mysql\\mysql_bootstrap.sql"  
#         EOT
#     }
# }


# resource "aws_glue_catalog_database" "aws_dl_db" {
#   name = "tickit_glue_db"
# }


# resource "aws_glue_connection" "tickit_glue_connection" {
#   connection_properties = {
#     JDBC_CONNECTION_URL = "jdbc:mysql://${aws_db_instance.datalake.endpoint}/${aws_db_instance.datalake.identifier}"
#     PASSWORD            = "admin"
#     USERNAME            = "12345678"
#   }

#   name = "tickit_glue_connection"

#   physical_connection_requirements {
#     availability_zone      = aws_availability_zones.available
#     security_group_id_list = [aws_security_group.rds.id] #[aws_security_group.example.id]
#     subnet_id              = module.vpc.public_subnets.id # aws_subnet.example.id
#   }
# }


# resource "aws_glue_crawler" "tickit_glue_crawler" {
#   database_name = aws_glue_catalog_database.aws_dl_db.name
#   name          = "tickit_mysql_crawler"
#   role          = aws_iam_role.gluerole.arn

#   jdbc_target {
#     connection_name = aws_glue_connection.tickit_glue_connection.name
#     path            = "tickit/%"
#   }
# }
