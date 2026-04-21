output "ssh_master" {
  value = "ssh ${var.ssh_user}@${module.vm_master.public_ip}"
}

output "ssh_workers" {
  value = [
    for m in module.vm_worker :
    "ssh ${var.ssh_user}@${m.public_ip}"
  ]
}

output "master_internal_ip" {
  value = module.vm_master.internal_ip
}