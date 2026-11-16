Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions", passwords: "users/passwords" }
  resource :two_factor_challenge, only: %i[new create]
  resource :account, only: %i[show] do
    patch :password
    patch :locale
    patch :default_key_account
  end
  resources :account_keys, only: %i[create destroy], path: "account/keys"
  resource :two_factor, only: %i[new create destroy], path: "account/two_factor", controller: "two_factor_settings" do
    post :backup_codes
  end
  resource :setup, only: %i[new create]
  get "invitations/:token", to: "invitations#show", as: :invitation_acceptance
  post "invitations/:token", to: "invitations#accept"

  # Before `resources :servers`, or /servers/groups would be a server's page.
  resources :server_groups, except: :show, path: "servers/groups"
  resource :server_columns, only: :update, path: "servers/columns"
  resource :server_inventories, only: :create, path: "servers/inventory"
  resource :server_import, only: %i[new create], path: "servers/import" do
    post :preview
  end
  resource :host_key_batch, only: %i[show create], path: "servers/host-keys"
  resources :servers do
    # Tests the SSH values of the form before saving (the edit form is sent as PATCH).
    match :test_connection, on: :collection, via: %i[post patch]
    resource :ping, only: %i[show create], controller: "server_pings"
    resource :ssh_check, only: :show, controller: "server_ssh_checks"
    resource :ssh_diagnosis, only: :show, controller: "server_ssh_diagnoses"
    resources :commands, only: :index, controller: "server_commands"
    resource :inventory, only: :create, controller: "server_inventories"
    resources :packages, only: :index, controller: "server_packages"
    resource :unit_journal, only: :show, controller: "server_unit_journals"
    resource :host_key, only: :create, controller: "server_host_keys"
    resource :expected_port, only: :create, controller: "server_expected_ports"
    resources :authorized_keys, only: :index, controller: "server_authorized_keys"
    resource :authorized_key, only: :destroy, controller: "server_authorized_keys"
    resources :authorizations, only: :create, controller: "server_authorizations"
    resources :my_key_accesses, only: %i[create destroy], path: "my-key"
    resources :temporary_accesses, only: %i[index update], path: "temporary-accesses"
    resources :notes, only: %i[create edit update destroy], controller: "server_notes" do
      post :preview, on: :collection
    end
  end
  resource :server_pings, only: :create, path: "servers/pings"
  resource :server_scans, only: :create, path: "servers/scans"

  resources :public_keys, path: "ssh-keys" do
    resources :accesses, only: :create, controller: "public_key_accesses"
    resource :access, only: :destroy, controller: "public_key_accesses"
  end

  resource :settings, only: %i[show update]
  namespace :settings do
    resource :dns_alerts, only: :update, path: "extensions/dns"
    resources :users, only: %i[index update] do
      member do
        post :deactivate
        post :reactivate
        post :reset_two_factor
        post :unlock
        post :require_password_change
      end
    end
    resources :invitations, only: %i[create destroy] do
      post :resend, on: :member
    end
    resource :security, only: :update
    resource :health_thresholds, only: :update
    resource :prompt_instructions, only: :update
    resource :firewall, only: :show
    resource :firewall_options, only: :update
    resources :ssh_sources, only: %i[create destroy] do
      patch :move, on: :member
    end
    resource :language, only: :update
    resource :docker, only: %i[show update], controller: "docker" do
      post :check
    end
    resources :score_providers, only: %i[new create edit update destroy], path: "vulnerabilities/providers" do
      member do
        patch :move
        patch :toggle
        post :test
      end
      post :preview, on: :collection
    end
    resource :vulnerabilities, only: %i[show update] do
      post :refresh
      post :import
      post :scores
    end
    resource :key_rotation_check, only: :create
    resources :key_rotations, only: %i[create show] do
      member do
        post :retry
        post :resume
        post :finalize
      end
    end
    resource :notifications, only: :show
    resources :notification_channels, except: %i[index show], path: "notifications/channels" do
      post :test, on: :member
    end
    resources :automations, only: %i[index update] do
      post :run, on: :member
    end
    patch "automations", to: "automations#update_all", as: :automations_update
    resources :integrations, only: %i[index edit update], param: :kind, path: "extensions" do
      member do
        match :test, via: %i[post patch] # (the button shares the settings form, sent as PATCH)
        post :sync
        delete :data, action: :purge
      end
      resources :connections, controller: "integration_connections", only: %i[new create edit update destroy] do
        post :test, on: :collection # (an unsaved connection)
        match :test, on: :member, via: %i[post patch]
      end
    end
  end
  # One event by its id only: /journal/runs stays the runs tab.
  # Quick search (⌘K): CVEs, packages and notes matching the typed text (JSON).
  get "search", to: "command_searches#index", as: :command_search
  resources :activities, only: %i[index show], path: "journal", constraints: { id: /\d+/ }
  resources :tasks, only: %i[index show], path: "journal/runs"
  post "journal/runs/:task_id/rerun", to: "task_reruns#create", as: :task_rerun
  post "journal/runs/:task_id/cancel", to: "task_cancellations#create", as: :task_cancellation
  resources :packages, only: :index, path: "updates"
  resources :ports, only: :index
  resources :scheduled_tasks, only: :index, path: "scheduled-tasks"
  resources :vulnerabilities, only: %i[index show], param: :cve, constraints: { cve: /[A-Za-z0-9-]+/ }
  get "docker", to: "docker#index", as: :docker
  get "docker/image_cves", to: "docker#image_cves", as: :docker_image_cves
  # Uptime Kuma extension.
  resources :monitors, only: :index do
    resource :link, only: %i[create destroy], controller: "monitor_links"
  end
  # OVHcloud extension.
  resource :dns_link_batch, only: :create, path: "dns/links"
  resources :dns_records, only: :index, path: "dns" do
    resource :link, only: %i[create destroy], controller: "dns_links"
  end
  get "hosting", to: "ovh#index", as: :ovh
  get "coolify", to: "coolify#index", as: :coolify
  resources :ovh_resources, only: [], path: "hosting/resources" do
    resource :link, only: %i[create destroy], controller: "ovh_links"
  end
  scope "settings" do
    resource :ssh_key, only: :create
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Content Security Policy violation reports of the browsers (no sign in).
  post "csp-reports" => "csp_reports#create", as: :csp_reports

  # Technical view of the background jobs (admins, see JobsDashboardController).
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Catalogue of the interface components, outside production.
  get "design" => "design#show" if Rails.env.local?

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Former addresses of renamed pages (bookmarks, links in old notifications).
  moved = ->(to) { redirect { |params, request| [ to.call(params), request.query_string.presence ].compact.join("?") } }
  get "keys(/*rest)", to: moved.(->(params) { [ "/ssh-keys", params[:rest] ].compact.join("/") }), format: false
  get "packages", to: moved.(->(_) { "/updates" })
  get "activities", to: moved.(->(_) { "/journal" })
  get "tasks(/:id)", to: moved.(->(params) { [ "/journal/runs", params[:id] ].compact.join("/") })
  get "ovh", to: moved.(->(_) { "/hosting" })

  # Defines the root path route ("/")
  root "dashboard#index"
end
