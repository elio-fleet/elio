require "application_system_test_case"

class UiTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:one)
  end

  test "toasts can be closed and disappear by themselves" do
    visit servers_path
    fleet_action "Scanner les clés de tout le parc"

    assert_selector "#flash .toast", text: "Scan des clés lancé"
    find("#flash .toast button[aria-label=Fermer]").click
    assert_no_selector "#flash .toast"

    visit servers_path
    fleet_action "Scanner les clés de tout le parc"
    assert_selector "#flash .toast"
    execute_script("document.querySelector('#flash [data-controller=toast]').dispatchEvent(new MouseEvent('mouseleave'))")
    assert_no_selector "#flash .toast", wait: 8
  end

  test "the confirm dialog uses the action's label and colour, and Escape cancels" do
    visit public_key_path(public_keys(:alice))
    click_on "Supprimer"

    within("#confirm-dialog[open]") do
      assert_text "La clé « Alice » sera retirée du trousseau."
      assert_selector "button[data-confirm-accept][data-variant=danger]", text: "Supprimer"
    end
    find("#confirm-dialog[open]").send_keys(:escape)
    assert_no_selector "#confirm-dialog[open]"
    assert_selector "h1", text: "Alice"
  end

  test "quick search finds a server and opens it with the keyboard" do
    visit root_path
    find("body").send_keys([ :control, "k" ])

    within("#command-palette[open]") do
      find("input[type=search]").fill_in(with: "dat")
      assert_selector ".command-palette-item[aria-selected=true]", text: /\ADatabase/
      find("input[type=search]").send_keys(:enter)
    end

    assert_selector "h1", text: "Database"
    assert_no_selector "#command-palette[open]"
  end

  test "quick search ignores accents and lists pages" do
    visit root_path
    find(".command-palette-button").click

    within("#command-palette[open]") do
      find("input[type=search]").fill_in(with: "parametres")
      assert_selector ".command-palette-item[aria-selected=true]", text: "Paramètres"
      find("input[type=search]").fill_in(with: "zzz")
      assert_text "Aucun résultat."
      assert_selector ".command-palette-item", count: 1, text: "Chercher le paquet « zzz » sur le parc"
    end
  end

  test "quick search reaches a server's tab, a package and a port" do
    visit root_path
    find("body").send_keys([ :control, "k" ])

    within("#command-palette[open]") do
      assert_no_selector ".command-palette-item", text: "›"
      find("input[type=search]").fill_in(with: "web paquets")
      assert_selector ".command-palette-item", text: "Web › Paquets"
      find("input[type=search]").send_keys(:enter)
    end
    assert_selector "nav.server-tabs a[aria-current=page][data-tab=packages]"

    find("body").send_keys([ :control, "k" ])
    within("#command-palette[open]") do
      find("input[type=search]").fill_in(with: "3306")
      assert_selector ".command-palette-item", text: "Qui expose le port 3306 ?"
      assert_selector ".command-palette-item", text: "Chercher le paquet « 3306 » sur le parc"
      find(".command-palette-item", text: "Qui expose le port 3306 ?").click
    end
    assert_field "q", with: "3306"
    assert_current_path ports_path(q: "3306")
  end

  test "authorizing a public_key on several servers at once" do
    granted = []
    granter = lambda do |server, _public_key, account:, **|
      granted << [ server.name, account.unix_user ]
      Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil)
    end
    reader = ->(*, **) { Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(public_keys(:alice).content), error_title: nil, error_details: nil) }

    stub_method(Keys::AccessGrant, :call, granter) do
      stub_method(Keys::AuthorizedKeysReader, :call, reader) do
        visit public_key_path(public_keys(:alice))
        within("#bulk-authorize") do
          click_on "Tout cocher / décocher"
          uncheck "Backup"
          click_on "Ajouter"

          assert_selector "li.bulk-result.is-success", count: 2
        end
        assert_selector "#key-accesses li.key-access", count: 2
      end
    end

    assert_equal [ [ "Database", "admin" ], [ "Web", "deploy" ] ], granted
  end

  test "converting a key without public_key into a public_key from the server page" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    reader = ->(*, **) { Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse([ ssh_keys(:main).public_key, bob ].join("\n")), error_title: nil, error_details: nil) }

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) do
      visit server_path(servers(:web), tab: "keys")

      within("#server-authorized-keys") do
        assert_selector ".orphan-warning", text: "1 clé n'est pas dans le trousseau"
        within("li.is-orphan", text: "bob@desktop") { click_on "Ajouter au trousseau" }
      end

      assert_selector "h1", text: "Ajouter une clé"
      assert_field "Nom", with: "bob"
      assert_field "Clé SSH publique", with: bob
      fill_in "Nom", with: "Bob"
      click_on "Ajouter au trousseau"

      assert_selector "#flash", text: "La clé « Bob » a été ajoutée au trousseau."
      assert_selector "h1", text: "Web"
      within("#server-authorized-keys") do
        assert_selector ".key-keyring", text: "Bob"
        assert_no_selector ".orphan-warning"
        assert_no_selector "li.is-orphan"
      end
    end
  end

  test "the theme switch turns the dark mode on and remembers it" do
    visit root_path
    page.execute_script("localStorage.removeItem('elio-theme')")
    visit root_path
    dark = -> { page.evaluate_script("document.documentElement.classList.contains('dark')") }
    initially_dark = dark.call

    find("button.theme-toggle").click
    assert_equal !initially_dark, dark.call
    assert_selector "button.theme-toggle", text: initially_dark ? "Thème sombre" : "Thème clair"

    visit public_keys_path
    assert_equal !initially_dark, dark.call
    assert_equal (initially_dark ? "light" : "dark"), page.evaluate_script("localStorage.getItem('elio-theme')")
  end
end
