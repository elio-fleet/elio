# Instructions of the administrator added at the end of the prompts for an AI
# (ServerPrompt): { "monitors" => "…", "firewall" => "…" }.
class AddPromptInstructionsToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :prompt_instructions, :jsonb, null: false, default: {}
  end
end
