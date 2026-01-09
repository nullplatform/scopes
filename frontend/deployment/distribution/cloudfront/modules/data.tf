data "aws_s3_bucket" "static" {
  bucket = var.distribution_bucket_name
}
