
provider "aws" {
	region = "ap-south-1"
	profile = "mohit-ka-eks"
}

provider "kubernetes" {
  load_config_file = "true"
}

# Fetching VPC or SubnetIDS
data "aws_vpcs" "eks-vpc" {
  tags = {
    service = "wp-eks"
  }
}
data "aws_subnet_ids" "subnetids" {
  vpc_id = element(tolist(data.aws_vpcs.eks-vpc.ids), 0 )
}


# Security Group for RDS
resource "aws_security_group" "rdssg" {
  name        = "db"
  description = "security group for webservers"
  vpc_id      = element(tolist(data.aws_vpcs.eks-vpc.ids), 0 )

  # Allowing traffic only for MySQL and that too from same VPC only.
  ingress {
    description = "MYSQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["172.168.0.0/16"]
  }

  # Allowing all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds sg"
  }
}


# DB subnet group 
resource "aws_db_subnet_group" "dbsubnet" {
  name       = "main"
  subnet_ids = tolist(data.aws_subnet_ids.subnetids.ids)
  tags = {
    Name = "My DB subnet group"
  }
}


# Creating DB instance 
resource "aws_db_instance" "mydb" {
  depends_on        = [aws_security_group.rdssg, aws_db_subnet_group.dbsubnet]
  allocated_storage = 20
  storage_type      = "gp2"
  # Using MYSQL engine for DB
  engine = "mysql"
  # Defining the Security Group Created
  vpc_security_group_ids = [aws_security_group.rdssg.id]
  engine_version         = "5.7.30"
  instance_class         = "db.t2.micro"
  # DB security group name to specify the VPC
  db_subnet_group_name  =  aws_db_subnet_group.dbsubnet.name
  # Giving Credentials
  name                 = "mywpdb"
  username             = "mohit"
  password             = "passmohit"
  parameter_group_name = "default.mysql5.7"
  # Making the RDS/ DB publicly accessible so that end point can be used
  publicly_accessible = true
  # Setting this true so that there will be no problem while destroying the Infrastructure as it won't create snapshot
  skip_final_snapshot = true

  tags = {
    Name = "mywpdb"
  }
}

# Deployment resources
resource "kubernetes_deployment" "mydeployment" {
  depends_on = [kubernetes_persistent_volume_claim.pvc, ]
  metadata {
    name = "mydeployment"
    labels = {
      app = "wp-frontend"
    }
  }
  # Spec for deployment
  spec {
    replicas = 3
    selector {
      match_labels = {
        app = "wp-frontend"
      }
    }
    template {
      metadata {
        labels = {
          app = "wp-frontend"
        }
      }
      # Spec for container
      spec {
        volume {
          name = "wordpress-persistent-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.pvc.metadata.0.name
          }
        
        }
        container {
          # Image to be used 
          image = "wordpress:4.8-apache"
          # Providing host, credentials and database name in environment variable
          env {
            name  = "WORDPRESS_DB_HOST"
            value = aws_db_instance.mydb.address
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = aws_db_instance.mydb.username
          }
          env {
            name  = "WORDPRESS_DB_PASSWORD"
            value = aws_db_instance.mydb.password
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = aws_db_instance.mydb.name
          }

          name = "wp-container"
          port {
            container_port = 80
          }
          volume_mount {
            name       = "wordpress-persistent-storage"
            mount_path = "/var/www/html"
          }
        }
      }
    }
  }
}


# Storage class, defining storage provisoner
resource "kubernetes_storage_class" "kubeSC" {
depends_on = [aws_db_instance.mydb,]
  metadata {
    name = "kubesc"
  }
  storage_provisioner = "kubernetes.io/aws-ebs"
  reclaim_policy      = "Retain"
  parameters = {
    type = "gp2"
  }
 }


# PVC 
resource "kubernetes_persistent_volume_claim" "pvc" {
depends_on = [kubernetes_storage_class.kubeSC,]
  metadata {
    name = "wp-pvc"
    labels = {
      app = "wp-frontend"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.kubeSC.metadata.0.name
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}


# LoadBalancer service 
resource "kubernetes_service" "mysvc" {
  depends_on = [kubernetes_deployment.mydeployment,]
  metadata {
    name = "wp-service"
    labels = {
      app = "wp-frontend"
    }
  }
  spec {
    selector = {
      app = "wp-frontend"
    }
    port {
      port = 80
    }
    type = "LoadBalancer"
  }
}


resource "time_sleep" "wait_120_seconds" {
  depends_on = [kubernetes_service.mysvc]

  create_duration = "120s"
}


resource "null_resource" "command" {
depends_on = [ time_sleep.wait_120_seconds, ]

  provisioner "local-exec" {
    
    command = "start chrome  ${kubernetes_service.mysvc.load_balancer_ingress.0.hostname}"
  }
}