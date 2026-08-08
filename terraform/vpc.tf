# ============================================================
# VPC - the private, isolated network everything else lives in
# ============================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# ============================================================
# Internet Gateway - the "front door." Without this attached,
# nothing in the VPC can reach or be reached from the internet,
# no matter what else is configured.
# ============================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ============================================================
# Public subnets - where the web app / load balancer will live.
# "Public" just means: has a route to the internet gateway.
# One per AZ for redundancy.
# ============================================================
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # instances launched here auto-get a public IP

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ============================================================
# Private subnets - where the database lives. No route to the
# internet gateway, so nothing outside the VPC can reach it
# directly, no matter what security group rules say.
# ============================================================
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ============================================================
# Public route table - the "directions" for public subnet traffic.
# This rule says: anything not headed within the VPC goes out
# through the internet gateway.
# ============================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0" # "anywhere on the internet"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# Private route table - intentionally has NO route to the internet
# gateway. Resources here (the database) can only be reached from
# inside the VPC. We're skipping a NAT Gateway (which would give
# private subnets outbound-only internet access) because it costs
# ~$32/month even when idle - not free-tier eligible. The database
# doesn't need outbound internet access anyway, so this is a
# reasonable trade-off for a portfolio build, not a shortcut that
# would fly in a real production environment with more budget.
# ============================================================
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
