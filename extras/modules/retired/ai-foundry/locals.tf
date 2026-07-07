locals {
  ai_project_roles = {
    ai_developer = {
      scope                = azurerm_ai_services.this.id
      role_definition_name = "Azure AI Developer"
      principal_id         = azurerm_ai_foundry_project.this.identity[0].principal_id
    }
  }

  ai_services_roles = {
    storage_blob_data_contributor = {
      scope                = var.storage_account_id
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = azurerm_ai_services.this.identity[0].principal_id
    }

    cognitive_services_openai_contributor_user = {
      scope                = azurerm_ai_services.this.id
      role_definition_name = "Cognitive Services OpenAI Contributor"
      principal_id         = var.user_object_id
    }

    cognitive_services_openai_contributor_search = {
      scope                = azurerm_ai_services.this.id
      role_definition_name = "Cognitive Services OpenAI Contributor"
      principal_id         = azurerm_search_service.this.identity[0].principal_id
    }

    cognitive_services_user = {
      scope                = azurerm_ai_services.this.id
      role_definition_name = "Cognitive Services User"
      principal_id         = var.user_object_id
    }
  }

  documents = [
    "CallScriptAudio.mp3",
    "Claim-Reporting-Script-Prompts.PropertyMgmt.pdf",
    "OmniServe_Agent_Performance.pdf",
    "OmniServe_Agent_Training.pdf",
    "OmniServe_Compliance_Policy.pdf",
    "OmniServe_CSAT_Guidelines.pdf"
  ]

  name_unique = regex("^.*-(.+)$", var.resource_group_name)[0]

  search_service_roles = {
    storage_blob_data_contributor = {
      scope                = var.storage_account_id
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = azurerm_search_service.this.identity[0].principal_id
    }

    search_index_data_contributor_user = {
      scope                = azurerm_search_service.this.id
      role_definition_name = "Search Index Data Contributor"
      principal_id         = var.user_object_id
    }

    search_index_data_contributor_ai_services = {
      scope                = azurerm_search_service.this.id
      role_definition_name = "Search Index Data Contributor"
      principal_id         = azurerm_ai_services.this.identity[0].principal_id
    }

    search_index_data_reader = {
      scope                = azurerm_search_service.this.id
      role_definition_name = "Search Index Data Reader"
      principal_id         = azurerm_ai_services.this.identity[0].principal_id
    }

    search_service_contributor = {
      scope                = azurerm_search_service.this.id
      role_definition_name = "Search Service Contributor"
      principal_id         = azurerm_ai_services.this.identity[0].principal_id
    }
  }
}
