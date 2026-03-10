module main

import time

// ---------------------------------------------------------------------------
// UI navigation enums
// ---------------------------------------------------------------------------

pub enum AppScreen {
	login
	main
}

pub enum ChannelType {
	stream
	direct
}

// ---------------------------------------------------------------------------
// Conversation represents either a stream+topic pair or a DM thread
// ---------------------------------------------------------------------------

pub struct Conversation {
pub mut:
	kind        ChannelType
	stream_id   int
	stream_name string
	topic       string
	// For DMs: the other party's email
	dm_email    string
	dm_name     string
	unread      int
}

fn (c &Conversation) id() string {
	return match c.kind {
		.stream  { 'stream:${c.stream_id}:${c.topic}' }
		.direct  { 'dm:${c.dm_email}' }
	}
}

fn (c &Conversation) display_name() string {
	return match c.kind {
		.stream  { c.topic }
		.direct  { c.dm_name }
	}
}

// ---------------------------------------------------------------------------
// Per-message state for optimistic UI feedback
// ---------------------------------------------------------------------------

pub struct PendingMessage {
pub mut:
	local_id    int
	content     string
	// true once the API confirmed it
	confirmed   bool
}

// ---------------------------------------------------------------------------
// Main application state
// ---------------------------------------------------------------------------

@[heap]
pub struct App {
pub mut:
	// ---- auth / connection ----
	screen        AppScreen = .login
	creds         ZulipCredentials
	client        ZulipClient

	// ---- login form ----
	login_server  string
	login_email   string
	login_api_key string
	login_error   string
	login_loading bool

	// ---- current user ----
	me ZulipUser

	// ---- sidebar data ----
	streams          []ZulipStream
	streams_loading  bool
	streams_error    string

	// stream_id -> []topic names (ordered newest-first)
	topics           map[int][]ZulipTopic
	expanded_streams map[int]bool
	// stream_id -> true while topics are being fetched
	topics_loading   map[int]bool

	// ---- active conversation ----
	active_conv      ?Conversation

	// ---- messages ----
	messages         []ZulipMessage
	messages_loading bool
	messages_error   string

	// Monotonically increasing counter for local pending message ids
	pending_seq      int
	pending_messages []PendingMessage

	// ---- compose box ----
	compose_text     string
	compose_loading  bool

	// ---- theme ----
	light_theme bool

	// ---- emoji picker ----
	// message id -> true when the quick-reaction picker is open for that message
	emoji_picker_open map[int]bool

	// ---- polling ----
	poll_running   bool
	last_event_id  int = -1
}

// ---------------------------------------------------------------------------
// Convenience helpers used from views
// ---------------------------------------------------------------------------

// active_stream returns the ZulipStream for the active conversation, if any.
fn (app &App) active_stream() ?ZulipStream {
	conv := app.active_conv or { return none }
	if conv.kind != .stream {
		return none
	}
	for s in app.streams {
		if s.stream_id == conv.stream_id {
			return s
		}
	}
	return none
}

// active_topic returns the topic string for the active stream conversation.
fn (app &App) active_topic() string {
	conv := app.active_conv or { return '' }
	if conv.kind != .stream {
		return ''
	}
	return conv.topic
}

// all_messages returns confirmed API messages plus any still-pending ones
// interleaved at the end so the user sees their own messages immediately.
fn (app &App) all_messages() []ZulipMessage {
	mut out := app.messages.clone()
	conv := app.active_conv or { return out }
	for p in app.pending_messages {
		if p.confirmed {
			continue
		}
		out << ZulipMessage{
			id:               -(p.local_id)
			sender_full_name: app.me.full_name
			sender_email:     app.me.email
			avatar_url:       app.me.avatar_url
			content:          p.content
			msg_type:         if conv.kind == .stream { 'stream' } else { 'private' }
			stream_id:        conv.stream_id
			subject:          conv.topic
			timestamp:        time.now().unix()
		}
	}
	return out
}

// topics_for returns the cached topics for a stream, or an empty slice.
fn (app &App) topics_for(stream_id int) []ZulipTopic {
	return app.topics[stream_id] or { []ZulipTopic{} }
}

// is_expanded returns whether the given stream is expanded in the sidebar.
fn (app &App) is_expanded(stream_id int) bool {
	return app.expanded_streams[stream_id] or { false }
}
