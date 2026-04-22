output "records" {
  value = [
    for r in cloudflare_record.app :
    r.hostname
  ]
}