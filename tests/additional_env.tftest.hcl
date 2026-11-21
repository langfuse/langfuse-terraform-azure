# Plans the module against mocked providers and checks the Helm values that
# additional_env renders. Run with `terraform test` (Terraform 1.7 or later).

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "time" {}

variables {
  domain = "langfuse.example.com"
}

run "additional_env_values_are_escaped" {
  command = plan

  variables {
    additional_env = [
      {
        name  = "JSON_CONFIG"
        value = "{\"key\": \"value\"}"
      },
      {
        name  = "WINDOWS_PATH"
        value = "C:\\langfuse\\data"
      },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.langfuse.values[4]).langfuse.additionalEnv[0].value == "{\"key\": \"value\"}"
    error_message = "additional_env values that contain double quotes must reach the Helm chart unchanged."
  }

  assert {
    condition     = yamldecode(helm_release.langfuse.values[4]).langfuse.additionalEnv[1].value == "C:\\langfuse\\data"
    error_message = "additional_env values that contain backslashes must reach the Helm chart unchanged."
  }
}
