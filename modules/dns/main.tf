terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

resource "cloudflare_record" "app" {
  count = length(var.ips)

  zone_id = var.zone_id
  name    = var.domain
  type    = "A"
  value   = var.ips[count.index]

  proxied = true
  ttl     = 1
}