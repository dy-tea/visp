module main

import gui

// ---------------------------------------------------------------------------
// Focus ID constants (centralised to avoid collisions across files)
// ---------------------------------------------------------------------------

// Login screen: 1-4 (defined in view_login.v)
// Messages scroll: 20, messages focus: 21
// Compose: 30-31
// Sidebar scroll: 10

fn main() {
	mut app := &App{}

	// Try to restore saved credentials on startup
	if creds := load_credentials() {
		app.login_server  = creds.server_url
		app.login_email   = creds.email
		app.login_api_key = creds.api_key
	}

	mut window := gui.window(
		title:        'Visp — Zulip Client'
		state:        app
		width:        1100
		height:       700
		cursor_blink: true
		on_init:      fn (mut w gui.Window) {
			w.update_view(root_view)
			w.set_id_focus(id_focus_server)

			// If credentials are saved, attempt auto-login
			a := w.state[App]()
			if a.login_server.len > 0 && a.login_email.len > 0 && a.login_api_key.len > 0 {
				action_login(mut w)
			}
		}
	)

	window.set_theme(gui.theme_dark_bordered)
	window.run()
}

// ---------------------------------------------------------------------------
// Root view — routes to the appropriate screen
// ---------------------------------------------------------------------------

fn root_view(window &gui.Window) gui.View {
	app := window.state[App]()
	return match app.screen {
		.login { view_login(window) }
		.main  { view_main(window) }
	}
}

// ---------------------------------------------------------------------------
// strings import shim — needed by zulip_api.v for strings.Builder
// ---------------------------------------------------------------------------
