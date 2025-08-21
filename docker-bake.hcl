group "default" {
  targets = ["php83", "php84"]
}

group "dev" {
  targets = ["php83-dev", "php84-dev"]
}

group "all" {
  targets = ["php83", "php84", "php83-dev", "php84-dev"]
}

target "base" {
  context   = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64", "linux/arm64"]
}

target "php83" {
  inherits = ["base"]
  tags     = ["bluegrassdigital/wordpress-azure-sync:8.3-latest", "bluegrassdigital/wordpress-azure-sync:8.3-stable"]
  args     = { PHP_VERSION = "8.3" }
}

target "php84" {
  inherits = ["base"]
  tags     = ["bluegrassdigital/wordpress-azure-sync:8.4-latest", "bluegrassdigital/wordpress-azure-sync:8.4-stable"]
  args     = { PHP_VERSION = "8.4" }
}

target "php83-dev" {
  inherits = ["base"]
  target   = "dev"
  tags     = ["bluegrassdigital/wordpress-azure-sync:8.3-dev-latest", "bluegrassdigital/wordpress-azure-sync:8.3-dev-stable"]
  args     = { PHP_VERSION = "8.3" }
}

target "php84-dev" {
  inherits = ["base"]
  target   = "dev"
  tags     = ["bluegrassdigital/wordpress-azure-sync:8.4-dev-latest", "bluegrassdigital/wordpress-azure-sync:8.4-dev-stable"]
  args     = { PHP_VERSION = "8.4" }
}
