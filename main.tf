
locals {
  project_id = var.project_id
}

resource "google_project_service" "compute_service" {
  project = local.project_id
  service = "compute.googleapis.com"
   disable_dependent_services = true
}
resource "google_compute_address" "static_ip" {
  name = format("%s-static-ip", var.instance_name)
}

resource "google_compute_network" "vpc_network" {
  name                    = format("%s-vpc",var.instance_name)
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_subnetwork" "private_network" {
  name          = "private-network"
  ip_cidr_range = "10.2.0.0/16"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_router" "router" {
  name    = format("%s-router",var.instance_name)
  network = google_compute_network.vpc_network.self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = format("%s-nat-route",var.instance_name)
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "default" {
  name    = format("%s-allow-ports", var.instance_name)
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "8000", "22", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]  # Allows traffic from any IP
}


resource "google_compute_route" "private_network_internet_route" {
  name             = format("%s-priv-net",var.instance_name)
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network.self_link
  next_hop_gateway = "default-internet-gateway"
  priority    = 100
}

resource "google_compute_instance" "vm_instance" {
  name         = format("%s-instance",var.instance_name)
  machine_type = var.machine_type

  tags = [format("%s-app",var.instance_name)]

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.private_network.self_link    
  
  access_config {
  #     // Optional: You can specify the NAT IP if you have a static IP. Otherwise, it will automatically assign an ephemeral IP.
    nat_ip = google_compute_address.static_ip.address
     }
   }
  metadata = {
    ssh-keys = "j.agboola:${file("~/.ssh/id_rsa.pub")}"
    startup-script = <<-EOT
                #!/bin/bash
                sudo apt-get update -y
                sudo apt-get upgrade -y
                sudo apt-get install -y docker.io
                sudo systemctl start docker
                sudo docker pull jeremy9k/tanto
                sudo docker run -d -p 80:8000 jeremy9k/tanto
                EOT
  }
}