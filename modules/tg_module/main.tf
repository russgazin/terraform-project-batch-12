resource "aws_lb_target_group" "target_group" {
  name     = var.name
  port     = var.port
  protocol = var.protocol
  vpc_id   = var.vpc_id

  tags = {
    Name = var.tg_tag
  }
}

resource "aws_lb_target_group_attachment" "ec2_attachment" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = var.instance_ids[count.index]
}
