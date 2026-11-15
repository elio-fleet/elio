# Domain folders (AUDIT.md R1-R3): they only group files, they are not
# namespaces. Server stays Server (tables, routes, views, jobs waiting in the
# queue unchanged), but app/models/fleet/server.rb sits with the rest of the
# fleet. Folders that ARE namespaces (Inventory::, Settings::, Users::,
# Integrations::) are not listed here.
DOMAIN_FOLDERS = {
  "app/models" => %w[fleet access accounts activity_log operations extensions security core],
  "app/controllers" => %w[fleet access accounts activity_log operations extensions security core],
  "app/jobs" => %w[access accounts activity_log operations security]
}.freeze

DOMAIN_FOLDERS.each do |root, folders|
  folders.each { |folder| Rails.autoloaders.main.collapse(Rails.root.join(root, folder)) }
end
