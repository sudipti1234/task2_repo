provider "aws" {
  region = "us-east-2"
  profile = "task-user"
}

// Step 1- Generating keys 

variable "key_name" {}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


// Step 2- creating a key pair in aws

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.key_name}"
  public_key = "${tls_private_key.example.public_key_openssh}"
}




variable "public_key"{
	default = "aws_key_pair.generated_key.key_name"
}

resource "local_file"  "private_key"{
 content = tls_private_key.example.private_key_pem
 filename = "${var.key_name}.pem"

depends_on = [
    tls_private_key.example,
    aws_key_pair.generated_key	
]
}


// Step 3- creating security group

resource "aws_security_group" "efs-task-sg" {
  name        = "allow_http"

  ingress {
    description = "allow http request"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "allow ssh request"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow  nfs request"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }  


  tags = {
    Name = "allow_http"
  }
}


//step 4 - downloading the images from git repo




resource "null_resource" "copying_images" {

  provisioner "local-exec"   {
    command = " echo 'git clone https://github.com/sudipti1234/wetsite.git'"
  
  } 
}


// Step 5- creating a s3 bucket

resource "aws_s3_bucket" "lwbucket15" {
  bucket = "lwbucket15" 
   acl    = "public-read"
 
  tags = {
    Name        = "lwbucket15"
  }
  versioning {
	enabled =true
  }

}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = "${aws_s3_bucket.lwbucket15.id}"

  block_public_acls   = false
  block_public_policy = false
}




// Step 6 - Creating bucket oblect

resource "aws_s3_bucket_object" "s3object" {
 depends_on = [
    aws_s3_bucket.lwbucket15,
  ]


  for_each = fileset("C:/Users/sudipti/Desktop/task2/wetsite/", "**/*.jpg")
 
   content_type="image/jpeg"  
   bucket = "${aws_s3_bucket.lwbucket15.id}"
   key           = replace(each.value, "C:/Users/sudipti/Desktop/task2/wetsite/", "")
  source = "C:/Users/sudipti/Desktop/task2/wetsite/${each.value}"
  acl    = "public-read" 
   }

output "bucket-details" {
value = aws_s3_bucket.lwbucket15
    }



// Step 7- creating cloudfront 

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
depends_on = [
    aws_s3_bucket_object.s3object,
  ]
  comment = "This is origin access identity"
}

output "origin_access" {
value = aws_cloudfront_origin_access_identity.origin_access_identity
}

resource "aws_cloudfront_distribution" "bucket_distribution" {

 depends_on = [
    aws_cloudfront_origin_access_identity.origin_access_identity,
  ]

    origin {
       // domain_name = "lwbucket15.s3.amazonaws.com"
        origin_id = "S3-lwbucket15" 


   domain_name = "${aws_s3_bucket.lwbucket15.bucket_regional_domain_name}"



        s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }
        enabled             = true
  	is_ipv6_enabled     = true


  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.lwbucket15.bucket_domain_name
   
  }

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-lwbucket15"


        # Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 10
        max_ttl = 30
    }
    //Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }


    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}

output "domain-details"{
	value  = aws_cloudfront_distribution.bucket_distribution.domain_name
}


//  Step 8 : Creating efs 

resource "aws_efs_file_system" "task2-efs" {
  creation_token = "task2-efs"
   performance_mode = "generalPurpose"
   throughput_mode = "bursting"
  tags = {
    Name = "task2-efs"
  }
}


resource "aws_efs_mount_target" "mount1" {
     subnet_id      = "subnet-789afb34"
   file_system_id  = "${aws_efs_file_system.task2-efs.id}"
   security_groups = ["${aws_security_group.efs-task-sg.id}"]
 }

resource "aws_efs_mount_target" "mount2" {
     subnet_id      = "subnet-8d2c15f7"
   file_system_id  = "${aws_efs_file_system.task2-efs.id}"
   security_groups = ["${aws_security_group.efs-task-sg.id}"]
 }

resource "aws_efs_mount_target" "mount3" {
     subnet_id      = "subnet-dba261b0"
   file_system_id  = "${aws_efs_file_system.task2-efs.id}"
   security_groups = ["${aws_security_group.efs-task-sg.id}"]
 }


// Step 9 : Launching ec2 instance



resource "aws_instance" "efs-instance" {

depends_on = [
        aws_key_pair.generated_key,
        aws_efs_file_system.task2-efs,
        aws_cloudfront_distribution.bucket_distribution,
  ]


  ami           = "ami-0a54aef4ef3b5f881"
  instance_type = "t2.micro"
  security_groups =  [ "${aws_security_group.efs-task-sg.name}" ]
   key_name	= "${var.key_name}"
  


connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem
    host     = aws_instance.efs-instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
        "sudo yum install php nfs-utils httpd git -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        "sudo mount -t nfs4  ${aws_efs_file_system.task2-efs.dns_name}:/ /var/www/html",
        "sudo su -c \"echo '${aws_efs_file_system.task2-efs.dns_name}:/  /var/www/html  nfs4  defaults,_netdev 0 0'  >> /etc/fstab\"" ,
        "sudo mount -fav",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/sudipti1234/wetsite.git  /var/www/html/",
        "sudo sed -i 's/src=\"/src=\"https:\\/\\/${aws_cloudfront_distribution.bucket_distribution.domain_name}\\//gI'  /var/www/html/* ",
        "sudo systemctl restart  httpd",
 ]

}

  tags = {
    Name = "webserver"
  }
}

// Step 10 : Saving the public ip in local machine
resource "null_resource" "save_ips"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.efs-instance.public_ip} > publicip.txt"
  	}
}

