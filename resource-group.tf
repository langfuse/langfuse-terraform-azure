resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name
  location = var.location
}
