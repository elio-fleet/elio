require "test_helper"

class PromptInstructionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "the general settings show one field per prompt, the monitors one only with Uptime Kuma" do
    get settings_path
    assert_select "#prompt-instructions textarea[name='prompt_instructions[firewall]'][placeholder*='port SSH']"
    assert_select "#prompt-instructions textarea[name='prompt_instructions[monitors]']", 0

    Integration.create!(kind: "uptime_kuma").update_column(:enabled, true)
    get settings_path
    assert_select "#prompt-instructions textarea[name='prompt_instructions[monitors]']"
  end

  test "saves the instructions, blanks dropped, unknown prompts ignored" do
    patch settings_prompt_instructions_path, params: { prompt_instructions: { firewall: "  SSH en dernier.\r\nMerci  ", monitors: " ", other: "x" } }

    assert_redirected_to settings_path(anchor: "prompt-instructions")
    assert_equal({ "firewall" => "SSH en dernier.\nMerci" }, AppSetting.current.prompt_instructions)
    assert_equal "SSH en dernier.\nMerci", AppSetting.current.prompt_instruction(:firewall)
    assert_nil AppSetting.current.prompt_instruction(:monitors)
  end

  test "refuses instructions that are too long" do
    patch settings_prompt_instructions_path, params: { prompt_instructions: { firewall: "a" * (AppSetting::PROMPT_INSTRUCTIONS_MAX + 1) } }
    assert_redirected_to settings_path(anchor: "prompt-instructions")
    assert_match "trop long", flash[:alert]
    assert_equal({}, AppSetting.current.reload.prompt_instructions)
  end

  test "the prompt says the instructions are included, with a link for the admins" do
    AppSetting.current.update!(prompt_instructions: { "firewall" => "SSH en dernier." })
    get Rails.application.routes.url_helpers.server_path(servers(:web), tab: "firewall")
    assert_select ".server-prompt[data-kind=firewall] .server-prompt-custom a[href=?]", settings_path(anchor: "prompt-instructions")

    sign_in users(:viewer)
    get Rails.application.routes.url_helpers.server_path(servers(:web), tab: "firewall")
    assert_select ".server-prompt[data-kind=firewall] .server-prompt-custom", text: /Vos consignes sont incluses/
    assert_select ".server-prompt-custom a", 0
  end
end
