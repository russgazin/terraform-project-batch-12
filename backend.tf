terraform {
  backend "s3" {
    bucket = "rustemtentech"
    region = "us-east-1"
    key    = "b12-project-sf"
  }
}
