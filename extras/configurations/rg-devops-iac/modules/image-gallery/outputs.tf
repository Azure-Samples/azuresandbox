output "resource_ids" {
  value = merge(
    {
      image_builder_identity = azurerm_user_assigned_identity.image_builder.id
      image_gallery          = azurerm_shared_image_gallery.this.id
    },
    { for key, image in azurerm_shared_image.images : "image_definition_${key}" => image.id },
    { for key, template in azapi_resource.image_templates : "image_template_${key}" => template.id }
  )
}

output "resource_names" {
  value = merge(
    {
      image_builder_identity = azurerm_user_assigned_identity.image_builder.name
      image_gallery          = azurerm_shared_image_gallery.this.name
    },
    { for key, image in azurerm_shared_image.images : "image_definition_${key}" => image.name },
    { for key, template in azapi_resource.image_templates : "image_template_${key}" => template.name }
  )
}
