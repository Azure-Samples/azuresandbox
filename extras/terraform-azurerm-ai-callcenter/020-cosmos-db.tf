# Adapted from:
#  https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/quickstart-terraform

resource "random_id" "cosmos_db_01" {
  byte_length = 8
}

resource "azurerm_cosmosdb_account" "cosmos_db_01" {
  name                       = "cos${random_id.cosmos_db_01.hex}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  offer_type                 = "Standard"
  kind                       = "GlobalDocumentDB"
  automatic_failover_enabled = false

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }
}

resource "azurerm_cosmosdb_sql_database" "cosmos_db_01" {
  name                = var.cosmos_db_01_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos_db_01.name
  throughput          = 400
}

resource "azurerm_cosmosdb_sql_container" "AI_Item" {
  name                  = "AI_Item"
  resource_group_name   = var.resource_group_name
  account_name          = azurerm_cosmosdb_account.cosmos_db_01.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos_db_01.name
  partition_key_kind    = "Hash"
  partition_key_paths   = ["/id"]
  partition_key_version = 2
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/_etag/?"
    }
  }

  unique_key {
    paths = []
  }

  conflict_resolution_policy {
    mode                     = "LastWriterWins"
    conflict_resolution_path = "/_ts"
  }
}

resource "azurerm_cosmosdb_sql_container" "chat_sessions" {
  name                  = "chat_sessions"
  resource_group_name   = var.resource_group_name
  account_name          = azurerm_cosmosdb_account.cosmos_db_01.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos_db_01.name
  partition_key_kind    = "Hash"
  partition_key_paths   = ["/partition_key"]
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/_etag/?"
    }
  }

  unique_key {
    paths = ["/partition_key"]
  }

  conflict_resolution_policy {
    mode                     = "LastWriterWins"
    conflict_resolution_path = "/_ts"
  }
}

resource "azurerm_cosmosdb_sql_container" "entities" {
  name                  = "entities"
  resource_group_name   = var.resource_group_name
  account_name          = azurerm_cosmosdb_account.cosmos_db_01.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos_db_01.name
  partition_key_kind    = "Hash"
  partition_key_paths   = ["/partition_key"]
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/_etag/?"
    }
  }

  unique_key {
    paths = [
      "/user_id",
      "/group_id",
      "/resource_id"
    ]
  }

  conflict_resolution_policy {
    mode                     = "LastWriterWins"
    conflict_resolution_path = "/_ts"
  }
}

resource "azurerm_cosmosdb_sql_container" "permissions" {
  name                  = "permissions"
  resource_group_name   = var.resource_group_name
  account_name          = azurerm_cosmosdb_account.cosmos_db_01.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos_db_01.name
  partition_key_kind    = "Hash"
  partition_key_paths   = ["/partition_key"]
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/_etag/?"
    }
  }

  unique_key {
    paths = ["/rule_id"]
  }

  conflict_resolution_policy {
    mode                     = "LastWriterWins"
    conflict_resolution_path = "/_ts"
  }
}

