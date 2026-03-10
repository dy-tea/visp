module main

import gui
import time
import encoding.base64
import os

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

fn action_login(mut w gui.Window) {
	mut app := w.state[App]()
	app.login_error = ''
	app.login_loading = true

	server := app.login_server.trim_space().trim_right('/')
	email := app.login_email.trim_space()
	api_key := app.login_api_key.trim_space()

	if server.len == 0 || email.len == 0 || api_key.len == 0 {
		app.login_error = 'Please fill in all fields.'
		app.login_loading = false
		return
	}

	creds := ZulipCredentials{
		server_url: server
		email:      email
		api_key:    api_key
	}
	client := ZulipClient{ creds: creds }

	spawn fn [creds, client, mut w] () {
		profile := client.fetch_profile() or {
			err_msg := err.msg()
			w.queue_command(fn [err_msg] (mut w gui.Window) {
				mut app := w.state[App]()
				app.login_error = 'Login failed: ${err_msg}'
				app.login_loading = false
			})
			return
		}

		save_credentials(creds) or {}

		w.queue_command(fn [creds, client, profile] (mut w gui.Window) {
			mut app := w.state[App]()
			app.creds         = creds
			app.client        = client
			app.me            = profile
			app.screen        = .main
			app.login_loading = false
		})

		// Register a link handler that intercepts Zulip narrow links so
		// clicking quoted message links navigates in-app rather than opening
		// the OS browser.
		w.queue_command(fn [creds] (mut w gui.Window) {
			server_url := creds.server_url
			w.set_link_handler(fn [server_url] (url string, mut e gui.Event, mut w gui.Window) {
				if nav := parse_narrow_link(url, server_url) {
					e.is_handled = true
					action_open_topic(nav.stream_id, nav.stream_name, nav.topic, mut w)
				}
			})
		})

		// Register an image auth callback so the GUI's image downloader
		// sends our Zulip credentials when fetching /user_uploads/ images.
		// Only send auth to the same server and only for restricted paths.
		w.queue_command(fn [creds] (mut w gui.Window) {
			server  := creds.server_url.trim_right('/')
			auth    := 'Basic ' + base64.encode_str('${creds.email}:${creds.api_key}')
			w.set_image_auth_header_fn(fn [server, auth] (url string) string {
				// Only authenticate requests to our own server's user_uploads
				if url.starts_with(server) && url.contains('/user_uploads/') {
					return auth
				}
				return ''
			})
		})

		w.queue_command(fn (mut w gui.Window) {
			action_load_streams(mut w)
			action_start_polling(mut w)
		})
	}()
}

// ---------------------------------------------------------------------------
// Load subscribed streams
// ---------------------------------------------------------------------------

fn action_load_streams(mut w gui.Window) {
	mut app := w.state[App]()
	app.streams_loading = true
	app.streams_error   = ''

	client := app.client

	spawn fn [client, mut w] () {
		streams := client.fetch_subscribed_streams() or {
			err_msg := err.msg()
			w.queue_command(fn [err_msg] (mut w gui.Window) {
				mut app := w.state[App]()
				app.streams_error   = 'Could not load channels: ${err_msg}'
				app.streams_loading = false
			})
			return
		}
		w.queue_command(fn [streams] (mut w gui.Window) {
			mut app := w.state[App]()
			app.streams         = streams
			app.streams_loading = false
		})
	}()
}

// ---------------------------------------------------------------------------
// Expand / collapse a stream in the sidebar and lazy-load its topics
// ---------------------------------------------------------------------------

fn action_toggle_stream(stream_id int, mut w gui.Window) {
	mut app := w.state[App]()
	currently := app.is_expanded(stream_id)
	app.expanded_streams[stream_id] = !currently

	// Fetch topics on first expansion; show loading indicator immediately
	if !currently && app.topics_for(stream_id).len == 0 && !app.topics_loading[stream_id] {
		app.topics_loading[stream_id] = true
		client := app.client
		spawn fn [client, stream_id, mut w] () {
			topics := client.fetch_topics(stream_id) or { []ZulipTopic{} }
			w.queue_command(fn [stream_id, topics] (mut w gui.Window) {
				mut app := w.state[App]()
				app.topics[stream_id]         = topics
				app.topics_loading[stream_id] = false
			})
		}()
	}
}

// ---------------------------------------------------------------------------
// Open a stream / topic conversation
// ---------------------------------------------------------------------------

fn action_open_topic(stream_id int, stream_name string, topic string, mut w gui.Window) {
	mut app := w.state[App]()
	conv := Conversation{
		kind:        .stream
		stream_id:   stream_id
		stream_name: stream_name
		topic:       topic
	}
	app.active_conv      = conv
	app.messages         = []
	app.messages_loading = true
	app.messages_error   = ''
	app.compose_text     = ''

	client := app.client

	spawn fn [client, stream_name, topic, mut w] () {
		msgs := client.fetch_stream_messages(stream_name, topic, 'newest') or {
			err_msg := err.msg()
			w.queue_command(fn [err_msg] (mut w gui.Window) {
				mut app := w.state[App]()
				app.messages_error   = 'Failed to load messages: ${err_msg}'
				app.messages_loading = false
			})
			return
		}
		w.queue_command(fn [msgs] (mut w gui.Window) {
			mut app := w.state[App]()
			app.messages         = msgs
			app.messages_loading = false
			w.scroll_vertical_to_pct(id_scroll_messages, 1.0)
		})
	}()
}

// ---------------------------------------------------------------------------
// Refresh messages for the active conversation
// ---------------------------------------------------------------------------

fn action_refresh_messages(mut w gui.Window) {
	app := w.state[App]()
	conv := app.active_conv or { return }
	if conv.kind == .stream {
		action_open_topic(conv.stream_id, conv.stream_name, conv.topic, mut w)
	}
}

// ---------------------------------------------------------------------------
// Send a message
// ---------------------------------------------------------------------------

fn action_send_message(mut w gui.Window) {
	mut app := w.state[App]()

	content := app.compose_text.trim_space()
	if content.len == 0 {
		return
	}

	conv := app.active_conv or { return }
	app.compose_text    = ''
	app.compose_loading = true

	// Optimistic local message
	app.pending_seq++
	local_id := app.pending_seq
	app.pending_messages << PendingMessage{
		local_id: local_id
		content:  content
	}

	w.scroll_vertical_to_pct(id_scroll_messages, 1.0)

	client := app.client

	match conv.kind {
		.stream {
			stream_name := conv.stream_name
			topic       := conv.topic
			spawn fn [client, stream_name, topic, content, local_id, mut w] () {
				client.send_stream_message(stream_name, topic, content) or {
					err_msg := err.msg()
					w.queue_command(fn [err_msg, local_id] (mut w gui.Window) {
						mut app := w.state[App]()
						app.compose_loading  = false
						app.pending_messages = app.pending_messages.filter(it.local_id != local_id)
						w.toast(gui.ToastCfg{
							title:    'Send failed'
							body:     err_msg
							severity: .error
						})
					})
					return
				}
				msgs := client.fetch_stream_messages(stream_name, topic, 'newest') or {
					// Best-effort reload failed; just clear loading state
					w.queue_command(fn [local_id] (mut w gui.Window) {
						mut app := w.state[App]()
						app.compose_loading  = false
						app.pending_messages = app.pending_messages.filter(it.local_id != local_id)
					})
					return
				}
				w.queue_command(fn [msgs, local_id] (mut w gui.Window) {
					mut app := w.state[App]()
					app.messages         = msgs
					app.compose_loading  = false
					app.pending_messages = app.pending_messages.filter(it.local_id != local_id)
					w.scroll_vertical_to_pct(id_scroll_messages, 1.0)
				})
			}()
		}
		.direct {
			dm_email := conv.dm_email
			spawn fn [client, dm_email, content, local_id, mut w] () {
				client.send_direct_message(dm_email, content) or {
					err_msg := err.msg()
					w.queue_command(fn [err_msg, local_id] (mut w gui.Window) {
						mut app := w.state[App]()
						app.compose_loading  = false
						app.pending_messages = app.pending_messages.filter(it.local_id != local_id)
						w.toast(gui.ToastCfg{
							title:    'Send failed'
							body:     err_msg
							severity: .error
						})
					})
					return
				}
				w.queue_command(fn [local_id] (mut w gui.Window) {
					mut app := w.state[App]()
					app.compose_loading  = false
					app.pending_messages = app.pending_messages.filter(it.local_id != local_id)
				})
			}()
		}
	}
}

// ---------------------------------------------------------------------------
// Poll for new messages every 10 s
// ---------------------------------------------------------------------------

fn action_start_polling(mut w gui.Window) {
	mut app := w.state[App]()
	if app.poll_running {
		return
	}
	app.poll_running = true

	spawn fn [mut w] () {
		for {
			time.sleep(10 * time.second)

			w.queue_command(fn (mut w gui.Window) {
				app := w.state[App]()
				if !app.poll_running || app.screen != .main {
					return
				}
				if app.messages_loading {
					return
				}
				conv := app.active_conv or { return }
				if conv.kind != .stream {
					return
				}
				client      := app.client
				stream_name := conv.stream_name
				topic       := conv.topic

				spawn fn [client, stream_name, topic, mut w] () {
					msgs := client.fetch_stream_messages(stream_name, topic, 'newest') or {
						return
					}
					w.queue_command(fn [msgs] (mut w gui.Window) {
						mut app := w.state[App]()
						if msgs.len > app.messages.len {
							app.messages = msgs
							pct := w.scroll_vertical_pct(id_scroll_messages)
							if pct > 0.85 {
								w.scroll_vertical_to_pct(id_scroll_messages, 1.0)
							}
						}
					})
				}()
			})
		}
	}()
}

fn action_stop_polling(mut w gui.Window) {
	mut app := w.state[App]()
	app.poll_running = false
}

// ---------------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Emoji reactions
// ---------------------------------------------------------------------------

fn action_toggle_reaction(msg_id int, emoji_name string, emoji_code string, reaction_type string, mut w gui.Window) {
	app := w.state[App]()
	client := app.client
	me_id := app.me.user_id

	// Check if current user has already reacted with this emoji
	already := app.messages.any(fn [msg_id, me_id, emoji_code] (m ZulipMessage) bool {
		if m.id != msg_id {
			return false
		}
		return m.reactions.any(fn [me_id, emoji_code] (r ZulipReaction) bool {
			return r.user_id == me_id && r.emoji_code == emoji_code
		})
	})

	// Optimistic in-place update so the UI responds immediately without a
	// full message reload (which resets scroll position and flickers).
	w.queue_command(fn [msg_id, emoji_name, emoji_code, reaction_type, me_id, already] (mut w gui.Window) {
		mut app := w.state[App]()
		for i in 0 .. app.messages.len {
			if app.messages[i].id == msg_id {
				if already {
					// Remove current user's reaction
					app.messages[i].reactions = app.messages[i].reactions.filter(
						!(it.user_id == me_id && it.emoji_code == emoji_code)
					)
				} else {
					// Add current user's reaction
					app.messages[i].reactions << ZulipReaction{
						emoji_name:    emoji_name
						emoji_code:    emoji_code
						reaction_type: reaction_type
						user_id:       me_id
					}
				}
				break
			}
		}
	})

	spawn fn [client, msg_id, emoji_name, emoji_code, reaction_type, already, mut w] () {
		if already {
			client.remove_reaction(msg_id, emoji_name, emoji_code, reaction_type) or {
				err_msg := err.msg()
				w.queue_command(fn [err_msg] (mut w gui.Window) {
					w.toast(gui.ToastCfg{
						title:    'Reaction failed'
						body:     err_msg
						severity: .error
					})
				})
				// Reload to undo the optimistic update
				w.queue_command(fn (mut w gui.Window) {
					action_refresh_messages(mut w)
				})
				return
			}
		} else {
			client.add_reaction(msg_id, emoji_name, emoji_code, reaction_type) or {
				err_msg := err.msg()
				w.queue_command(fn [err_msg] (mut w gui.Window) {
					w.toast(gui.ToastCfg{
						title:    'Reaction failed'
						body:     err_msg
						severity: .error
					})
				})
				// Reload to undo the optimistic update
				w.queue_command(fn (mut w gui.Window) {
					action_refresh_messages(mut w)
				})
				return
			}
		}
		// Fetch only the single message to sync server-side reaction state
		// (e.g. other users may have reacted concurrently).
		updated := client.fetch_single_message(msg_id) or {
			// Best-effort — ignore network errors here; UI already reflects
			// the optimistic state which is almost certainly correct.
			return
		}
		w.queue_command(fn [msg_id, updated] (mut w gui.Window) {
			mut app := w.state[App]()
			for i in 0 .. app.messages.len {
				if app.messages[i].id == msg_id {
					app.messages[i].reactions = updated.reactions
					break
				}
			}
		})
	}()
}

// ---------------------------------------------------------------------------
// File upload / image attachment
// ---------------------------------------------------------------------------

// action_pick_and_upload_file opens the native file picker and, on selection,
// uploads the chosen file to the Zulip server, then inserts a markdown link
// (or image embed) into the compose box.
fn action_pick_and_upload_file(mut w gui.Window) {
	w.native_open_dialog(gui.NativeOpenDialogCfg{
		title:          'Attach a file'
		allow_multiple: false
		filters:        [
			gui.NativeFileFilter{
				name:       'Images'
				extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg']
			},
			gui.NativeFileFilter{
				name:       'All files'
				extensions: ['*']
			},
		]
		on_done: on_file_picked
	})
}

// on_file_picked is the NativeOpenDialog callback: uploads the selected file
// and inserts the resulting markdown link into the compose text.
fn on_file_picked(result gui.NativeDialogResult, mut w gui.Window) {
	if result.status != .ok {
		return
	}
	paths := result.path_strings()
	if paths.len == 0 {
		return
	}
	file_path := paths[0]
	app := w.state[App]()
	client := app.client

	mut app2 := w.state[App]()
	app2.compose_loading = true

	spawn action_do_upload(client, file_path, mut w)
}

// action_do_upload performs the actual HTTP upload and updates compose text.
fn action_do_upload(client ZulipClient, file_path string, mut w gui.Window) {
	uri := client.upload_file(file_path) or {
		err_msg := err.msg()
		w.queue_command(fn [err_msg] (mut w gui.Window) {
			mut app := w.state[App]()
			app.compose_loading = false
			w.toast(gui.ToastCfg{
				title:    'Upload failed'
				body:     err_msg
				severity: .error
			})
		})
		return
	}
	// Build a markdown image embed for image files, plain link otherwise
	file_name := os.base(file_path)
	ext_lower := os.file_ext(file_name).to_lower()
	img_exts  := ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg']
	is_image  := ext_lower in img_exts
	link := if is_image {
		'![${file_name}](${uri})'
	} else {
		'[${file_name}](${uri})'
	}
	w.queue_command(fn [link] (mut w gui.Window) {
		mut app := w.state[App]()
		app.compose_loading = false
		// Append the link to whatever is already in the compose box
		sep := if app.compose_text.len > 0 && !app.compose_text.ends_with('\n') {
			'\n'
		} else {
			''
		}
		app.compose_text = app.compose_text + sep + link
	})
}

// ---------------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------------

fn action_logout(mut w gui.Window) {
	action_stop_polling(mut w)
	mut app := w.state[App]()
	app.screen             = .login
	app.creds              = ZulipCredentials{}
	app.client             = ZulipClient{}
	app.me                 = ZulipUser{}
	app.streams            = []ZulipStream{}
	app.topics             = map[int][]ZulipTopic{}
	app.expanded_streams   = map[int]bool{}
	app.messages           = []ZulipMessage{}
	app.active_conv        = none
	app.compose_text       = ''
	app.emoji_picker_open  = map[int]bool{}

	// Remove auth/link hooks so they don't survive after logout
	w.set_link_handler(none)
	w.set_image_auth_header_fn(none)

	save_credentials(ZulipCredentials{}) or {}
}
