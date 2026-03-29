/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.StockWidletItem : ContainerItem {
    private const string SYMBOLS_KEY = "widlet-stock-symbols";
    private const string ROTATION_SECONDS_KEY = "widlet-stock-rotation-seconds";

    private const int CARD_WIDTH = 160;
    private const int CARD_OUTER_WIDTH = CARD_WIDTH + Launcher.PADDING * 2;
    private const uint DATA_REFRESH_SECONDS = 60;
    private const int CACHE_STALE_SECONDS = 45;
    private const int DEFAULT_ROTATION_SECONDS = 8;
    private const int MIN_ROTATION_SECONDS = 2;
    private const int MAX_ROTATION_SECONDS = 300;

    private class DetailsPopover : Gtk.Popover {
        class construct {
            set_css_name ("tooltip");
        }
    }

    private class QuoteSnapshot : Object {
        public string symbol { get; set; default = ""; }
        public string company_name { get; set; default = ""; }
        public string currency { get; set; default = "USD"; }
        public double price { get; set; default = 0; }
        public double change_percent { get; set; default = 0; }
        public double previous_close { get; set; default = 0; }
        public double day_high { get; set; default = 0; }
        public double day_low { get; set; default = 0; }
        public int64 volume { get; set; default = 0; }
        public double[] trend_values = {};
        public int64 updated_at_unix { get; set; default = 0; }
        public bool has_data { get; set; default = false; }
    }

    private static Soup.Session? soup_session = null;

    private Gtk.Stack logo_stack;
    private Gtk.Image logo_image;
    private Gtk.Label logo_fallback_label;

    private Gtk.Label symbol_label;
    private Gtk.Label company_label;
    private Gtk.Label price_label;
    private Gtk.Label change_label;

    private Gtk.DrawingArea sparkline_area;

    private Gtk.Label details_symbol_value_label;
    private Gtk.Label details_company_value_label;
    private Gtk.Label details_price_value_label;
    private Gtk.Label details_change_value_label;
    private Gtk.Label details_day_range_value_label;
    private Gtk.Label details_prev_close_value_label;
    private Gtk.Label details_volume_value_label;
    private Gtk.Overlay card_overlay;

    private uint rotation_timeout_id = 0;
    private uint refresh_timeout_id = 0;
    private uint active_request_serial = 0;
    private uint logo_request_serial = 0;
    private string logo_disk_cache_dir = "";

    private string current_trend_css_class = "";
    private string current_change_css_class = "";

    private string[] symbols = {};
    private int current_symbol_index = 0;
    private GLib.HashTable<string, QuoteSnapshot> quote_cache;
    private GLib.HashTable<string, Gdk.Texture> logo_cache;
    private GLib.HashTable<string, string> tradingview_logoid_cache;

    private string current_symbol = "";
    private string current_company = "";
    private string current_currency = "USD";
    private double current_price = 0;
    private double current_change_percent = 0;
    private double current_day_high = 0;
    private double current_day_low = 0;
    private double current_previous_close = 0;
    private int64 current_volume = 0;
    private double[] current_trend_values = {};
    private bool has_current_data = false;

    public StockWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    protected override int get_width_for_icon_size (int icon_size) {
        return CARD_WIDTH;
    }

    public int get_dock_width () {
        return CARD_OUTER_WIDTH;
    }

    construct {
        quote_cache = new GLib.HashTable<string, QuoteSnapshot> (str_hash, str_equal);
        logo_cache = new GLib.HashTable<string, Gdk.Texture> (str_hash, str_equal);
        tradingview_logoid_cache = new GLib.HashTable<string, string> (str_hash, str_equal);
        logo_disk_cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "dockx", "stock-logos");

        try {
            DirUtils.create_with_parents (logo_disk_cache_dir, 0755);
        } catch (Error e) {
            warning ("Could not create stock logo cache dir '%s': %s", logo_disk_cache_dir, e.message);
        }

        add_css_class ("stock-widlet-item");

        logo_image = new Gtk.Image () {
            pixel_size = 20,
            halign = CENTER,
            valign = CENTER,
            can_target = false
        };
        logo_image.add_css_class ("stock-widlet-logo");

        logo_fallback_label = new Gtk.Label ("S") {
            halign = CENTER,
            valign = CENTER,
            can_target = false
        };
        logo_fallback_label.add_css_class ("stock-widlet-logo-fallback-label");

        var logo_fallback = new Gtk.Box (HORIZONTAL, 0) {
            width_request = 20,
            height_request = 20,
            halign = CENTER,
            valign = CENTER,
            can_target = false
        };
        logo_fallback.add_css_class ("stock-widlet-logo-fallback");
        logo_fallback.append (logo_fallback_label);

        logo_stack = new Gtk.Stack () {
            transition_type = NONE,
            width_request = 20,
            height_request = 20,
            hhomogeneous = true,
            vhomogeneous = true,
            halign = START,
            valign = START,
            overflow = HIDDEN,
            can_target = false
        };
        logo_stack.add_css_class ("stock-widlet-logo-wrap");
        logo_stack.add_named (logo_image, "logo");
        logo_stack.add_named (logo_fallback, "fallback");
        logo_stack.visible_child_name = "fallback";

        symbol_label = new Gtk.Label ("TSLA") {
            xalign = 0,
            hexpand = true,
            halign = FILL
        };
        symbol_label.add_css_class ("stock-widlet-symbol");

        company_label = new Gtk.Label (_("Loading...")) {
            xalign = 0,
            hexpand = true,
            halign = FILL,
            single_line_mode = true,
            ellipsize = Pango.EllipsizeMode.END
        };
        company_label.add_css_class ("stock-widlet-company");

        price_label = new Gtk.Label ("--") {
            xalign = 1,
            halign = END
        };
        price_label.add_css_class ("stock-widlet-price");

        change_label = new Gtk.Label ("--") {
            xalign = 1,
            halign = END
        };
        change_label.add_css_class ("stock-widlet-change");

        var top_content = new Gtk.Grid () {
            column_spacing = 6,
            row_spacing = 0,
            margin_start = 9,
            margin_end = 7,
            margin_top = 6,
            margin_bottom = 14,
            valign = START,
            hexpand = true,
            can_target = false
        };
        top_content.add_css_class ("stock-widlet-top");
        top_content.attach (logo_stack, 0, 0, 1, 2);
        top_content.attach (symbol_label, 1, 0, 1, 1);
        top_content.attach (company_label, 1, 1, 1, 1);
        top_content.attach (price_label, 2, 0, 1, 1);
        top_content.attach (change_label, 2, 1, 1, 1);

        sparkline_area = new Gtk.DrawingArea () {
            halign = FILL,
            valign = END,
            margin_start = 1,
            margin_end = 1,
            margin_bottom = 1,
            height_request = 13,
            can_target = false
        };
        sparkline_area.set_draw_func ((area, cr, width, height) => {
            draw_sparkline (cr, width, height);
        });

        var content = new Gtk.Overlay () {
            child = new Gtk.Box (HORIZONTAL, 0),
            overflow = HIDDEN,
            valign = FILL,
            vexpand = true
        };
        content.add_css_class ("stock-widlet-content");
        content.add_overlay (sparkline_area);
        content.set_measure_overlay (sparkline_area, false);
        content.add_overlay (top_content);
        content.set_measure_overlay (top_content, false);
        card_overlay = content;

        child = content;
        notify["icon-size"].connect (update_size_variant);
        update_size_variant ();

        var details_title = new Gtk.Label (_("Stock Details")) {
            xalign = 0
        };
        details_title.add_css_class ("widlet-details-title");

        var details_grid = new Gtk.Grid () {
            column_spacing = 14,
            row_spacing = 6
        };
        details_grid.add_css_class ("widlet-details-grid");

        add_details_row (details_grid, 0, _("Symbol"), out details_symbol_value_label);
        add_details_row (details_grid, 1, _("Company"), out details_company_value_label);
        add_details_row (details_grid, 2, _("Price"), out details_price_value_label);
        add_details_row (details_grid, 3, _("Change"), out details_change_value_label);
        add_details_row (details_grid, 4, _("Day Range"), out details_day_range_value_label);
        add_details_row (details_grid, 5, _("Prev Close"), out details_prev_close_value_label);
        add_details_row (details_grid, 6, _("Volume"), out details_volume_value_label);

        var details_content = new Gtk.Box (VERTICAL, 8) {
            margin_start = 10,
            margin_end = 10,
            margin_top = 8,
            margin_bottom = 8,
            width_request = 280
        };
        details_content.add_css_class ("widlet-details-popover");
        details_content.append (details_title);
        details_content.append (new Gtk.Separator (HORIZONTAL));
        details_content.append (details_grid);

        popover_menu = new DetailsPopover () {
            autohide = true,
            position = TOP,
            has_arrow = false,
            child = details_content
        };
        popover_menu.set_offset (0, -1);
        popover_menu.set_parent (this);

        gesture_click.button = 0;
        gesture_click.released.connect (on_click_released);

        if (dock_settings.settings_schema.has_key (SYMBOLS_KEY)) {
            dock_settings.changed[SYMBOLS_KEY].connect (() => {
                reload_symbols_from_settings ();
                refresh_current_symbol.begin (true);
            });
        }

        if (dock_settings.settings_schema.has_key (ROTATION_SECONDS_KEY)) {
            dock_settings.changed[ROTATION_SECONDS_KEY].connect (restart_rotation_timer);
        }

        reload_symbols_from_settings ();

        refresh_timeout_id = Timeout.add_seconds (DATA_REFRESH_SECONDS, () => {
            refresh_current_symbol.begin (true);
            return Source.CONTINUE;
        });

        refresh_current_symbol.begin (true);
    }

    ~StockWidletItem () {
        if (rotation_timeout_id != 0) {
            Source.remove (rotation_timeout_id);
            rotation_timeout_id = 0;
        }

        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }

        popover_menu.unparent ();
        popover_menu.dispose ();
    }

    private static void add_details_row (Gtk.Grid grid, int row, string key, out Gtk.Label value_label) {
        var key_label = new Gtk.Label (key) {
            xalign = 0,
            halign = START
        };
        key_label.add_css_class ("widlet-details-key");

        value_label = new Gtk.Label ("--") {
            xalign = 1,
            halign = END
        };
        value_label.add_css_class ("widlet-details-value");

        grid.attach (key_label, 0, row, 1, 1);
        grid.attach (value_label, 1, row, 1, 1);
    }

    private void on_click_released (int n_press, double x, double y) {
        var current_button = gesture_click.get_current_button ();
        if (current_button != Gdk.BUTTON_PRIMARY && current_button != Gdk.BUTTON_SECONDARY) {
            return;
        }

        if (popover_menu.visible) {
            popover_menu.popdown ();
            return;
        }

        refresh_details_labels ();
        popover_tooltip.popdown ();
        popover_menu.popup ();
    }

    private void reload_symbols_from_settings () {
        var raw = "TSLA";
        if (dock_settings.settings_schema.has_key (SYMBOLS_KEY)) {
            raw = dock_settings.get_string (SYMBOLS_KEY);
        }

        var parsed = parse_symbols (raw);
        if (parsed.length == 0) {
            parsed = {"TSLA"};
        }

        symbols = parsed;
        if (current_symbol == "" || !contains_symbol (symbols, current_symbol)) {
            current_symbol_index = 0;
            current_symbol = symbols[current_symbol_index];
        } else {
            current_symbol_index = get_symbol_index (current_symbol);
        }

        restart_rotation_timer ();
        update_symbol_labels ();
    }

    private bool contains_symbol (string[] list, string symbol) {
        foreach (var item in list) {
            if (item == symbol) {
                return true;
            }
        }

        return false;
    }

    private int get_symbol_index (string symbol) {
        for (int i = 0; i < symbols.length; i++) {
            if (symbols[i] == symbol) {
                return i;
            }
        }

        return 0;
    }

    private static string[] parse_symbols (string raw_symbols) {
        string[] parsed = {};

        foreach (var chunk in raw_symbols.split (",")) {
            foreach (var token in chunk.split (";")) {
                foreach (var piece in token.split (" ")) {
                    var symbol = sanitize_symbol (piece);
                    if (symbol == "") {
                        continue;
                    }

                    bool duplicate = false;
                    foreach (var existing in parsed) {
                        if (existing == symbol) {
                            duplicate = true;
                            break;
                        }
                    }

                    if (!duplicate) {
                        parsed += symbol;
                    }
                }
            }
        }

        return parsed;
    }

    private static string sanitize_symbol (string raw_symbol) {
        var symbol = raw_symbol.strip ().up ();
        if (symbol == "") {
            return "";
        }

        try {
            var regex = new Regex ("[^A-Z0-9\\.\\-\\^=]");
            symbol = regex.replace (symbol, -1, 0, "");
        } catch (Error e) {
            warning ("Could not sanitize stock symbol '%s': %s", raw_symbol, e.message);
        }

        return symbol.strip ();
    }

    private void restart_rotation_timer () {
        if (rotation_timeout_id != 0) {
            Source.remove (rotation_timeout_id);
            rotation_timeout_id = 0;
        }

        if (symbols.length <= 1) {
            return;
        }

        rotation_timeout_id = Timeout.add_seconds ((uint) get_rotation_seconds (), () => {
            rotate_to_next_symbol ();
            return Source.CONTINUE;
        });
    }

    private int get_rotation_seconds () {
        if (!dock_settings.settings_schema.has_key (ROTATION_SECONDS_KEY)) {
            return DEFAULT_ROTATION_SECONDS;
        }

        var configured = dock_settings.get_int (ROTATION_SECONDS_KEY);
        if (configured < MIN_ROTATION_SECONDS) {
            return MIN_ROTATION_SECONDS;
        }
        if (configured > MAX_ROTATION_SECONDS) {
            return MAX_ROTATION_SECONDS;
        }

        return configured;
    }

    private void rotate_to_next_symbol () {
        if (symbols.length == 0) {
            return;
        }

        current_symbol_index = (current_symbol_index + 1) % symbols.length;
        current_symbol = symbols[current_symbol_index];
        update_symbol_labels ();
        refresh_current_symbol.begin (false);
    }

    private async void refresh_current_symbol (bool force_network) {
        if (symbols.length == 0) {
            return;
        }

        current_symbol = symbols[current_symbol_index];
        var cache_item = quote_cache.lookup (current_symbol);
        var now = get_unix_seconds ();

        if (!force_network && cache_item != null && (now - cache_item.updated_at_unix) <= CACHE_STALE_SECONDS) {
            apply_snapshot (cache_item);
            return;
        }

        var request_serial = ++active_request_serial;
        yield fetch_symbol_data (current_symbol, request_serial);
    }

    private async void fetch_symbol_data (string symbol, uint request_serial) {
        if (soup_session == null) {
            soup_session = new Soup.Session () {
                timeout = 10
            };
        }

        string body = "";
        string[] urls = {
            "https://query2.finance.yahoo.com/v8/finance/chart/%s?interval=5m&range=1d&includePrePost=false".printf (Uri.escape_string (symbol, null, false)),
            "https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=5m&range=1d&includePrePost=false".printf (Uri.escape_string (symbol, null, false)),
            "https://query2.finance.yahoo.com/v8/finance/chart/%s?interval=1d&range=5d&includePrePost=false".printf (Uri.escape_string (symbol, null, false)),
            "https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&range=5d&includePrePost=false".printf (Uri.escape_string (symbol, null, false))
        };

        Error? last_error = null;
        bool loaded = false;

        foreach (var url in urls) {
            try {
                var message = new Soup.Message ("GET", url);
                message.request_headers.append ("User-Agent", "Mozilla/5.0 (dockx widlet)");
                message.request_headers.append ("Accept", "*/*");
                message.request_headers.append ("Referer", "https://finance.yahoo.com/");

                var bytes = yield soup_session.send_and_read_async (message, Priority.DEFAULT, null);
                if (message.status_code != Soup.Status.OK) {
                    throw new IOError.FAILED ("Unexpected stock response HTTP %u".printf (message.status_code));
                }

                body = (string) bytes.get_data ();
                loaded = true;
                break;
            } catch (Error e) {
                last_error = e;
            }
        }

        if (!loaded) {
            var failure_snapshot = new QuoteSnapshot () {
                symbol = symbol,
                company_name = symbol,
                has_data = false,
                updated_at_unix = get_unix_seconds ()
            };
            quote_cache.insert (symbol, failure_snapshot);

            if (request_serial == active_request_serial && symbol == current_symbol) {
                apply_snapshot (failure_snapshot);
            }

            if (last_error != null) {
                warning ("Failed to fetch stock data for %s: %s", symbol, last_error.message);
            }
            return;
        }

        var snapshot = parse_quote_snapshot (symbol, body);
        quote_cache.insert (symbol, snapshot);

        if (request_serial == active_request_serial && symbol == current_symbol) {
            apply_snapshot (snapshot);
        }
    }

    private QuoteSnapshot parse_quote_snapshot (string symbol, string payload) {
        var snapshot = new QuoteSnapshot () {
            symbol = symbol,
            company_name = symbol,
            currency = "USD",
            updated_at_unix = get_unix_seconds ()
        };

        string company_name;
        if (parse_string_field (payload, "longName", out company_name) && company_name != "") {
            snapshot.company_name = company_name;
        } else if (parse_string_field (payload, "shortName", out company_name) && company_name != "") {
            snapshot.company_name = company_name;
        }

        string currency;
        if (parse_string_field (payload, "currency", out currency) && currency != "") {
            snapshot.currency = currency;
        }

        double price;
        if (!parse_double_field (payload, "regularMarketPrice", out price)) {
            warning ("Missing regularMarketPrice in stock response for %s", symbol);
            snapshot.has_data = false;
            return snapshot;
        }
        snapshot.price = price;

        double previous_close;
        if (parse_double_field (payload, "chartPreviousClose", out previous_close) ||
            parse_double_field (payload, "previousClose", out previous_close)) {
            snapshot.previous_close = previous_close;
        }

        if (snapshot.previous_close > 0) {
            snapshot.change_percent = ((snapshot.price - snapshot.previous_close) / snapshot.previous_close) * 100.0;
        }

        double day_high;
        if (parse_double_field (payload, "regularMarketDayHigh", out day_high)) {
            snapshot.day_high = day_high;
        }

        double day_low;
        if (parse_double_field (payload, "regularMarketDayLow", out day_low)) {
            snapshot.day_low = day_low;
        }

        double volume;
        if (parse_double_field (payload, "regularMarketVolume", out volume)) {
            snapshot.volume = (int64) Math.round (volume);
        }

        double[] close_values;
        if (parse_nullable_double_array_field (payload, "close", out close_values) && close_values.length > 0) {
            snapshot.trend_values = normalize_trend_values (close_values);
        }

        if (snapshot.trend_values.length == 0) {
            if (snapshot.previous_close > 0) {
                snapshot.trend_values = {snapshot.previous_close, snapshot.price};
            } else {
                snapshot.trend_values = {snapshot.price, snapshot.price};
            }
        }

        snapshot.has_data = true;
        return snapshot;
    }

    private void apply_snapshot (QuoteSnapshot snapshot) {
        current_symbol = snapshot.symbol;
        current_company = snapshot.company_name;
        current_currency = snapshot.currency;
        current_price = snapshot.price;
        current_change_percent = snapshot.change_percent;
        current_day_high = snapshot.day_high;
        current_day_low = snapshot.day_low;
        current_previous_close = snapshot.previous_close;
        current_volume = snapshot.volume;
        current_trend_values = snapshot.trend_values;
        has_current_data = snapshot.has_data;

        symbol_label.label = current_symbol;
        company_label.label = current_company != "" ? current_company : current_symbol;
        logo_fallback_label.label = symbol_to_badge (current_symbol);

        if (!has_current_data) {
            price_label.label = "--";
            change_label.label = "--";
            set_trend_classes (0);
            tooltip_text = _("%s\nStock data unavailable").printf (current_symbol);
            logo_stack.visible_child_name = "fallback";
            sparkline_area.queue_draw ();
            refresh_details_labels ();
            return;
        }

        price_label.label = format_price (current_price, current_currency);
        change_label.label = format_percent (current_change_percent);
        set_trend_classes (current_change_percent);
        tooltip_text = _("%s · %s\n%s (%s)").printf (
            current_symbol,
            current_company,
            price_label.label,
            change_label.label
        );

        update_logo_for_symbol (current_symbol, current_company);
        sparkline_area.queue_draw ();
        refresh_details_labels ();
    }

    private void update_logo_for_symbol (string symbol, string company_name) {
        var cached = logo_cache.lookup (symbol);
        if (cached != null) {
            logo_image.paintable = cached;
            logo_stack.visible_child_name = "logo";
            return;
        }

        Gdk.Texture? disk_texture = null;
        if (load_logo_from_disk (symbol, out disk_texture) && disk_texture != null) {
            logo_cache.insert (symbol, disk_texture);
            logo_image.paintable = disk_texture;
            logo_stack.visible_child_name = "logo";
            return;
        }

        logo_stack.visible_child_name = "fallback";
        var request_serial = ++logo_request_serial;
        load_remote_logo.begin (symbol, company_name, request_serial);
    }

    private async void load_remote_logo (string symbol, string company_name, uint request_serial) {
        if (soup_session == null) {
            soup_session = new Soup.Session () {
                timeout = 10
            };
        }

        var tradingview_logoid = yield resolve_tradingview_logoid (symbol);
        foreach (var url in get_logo_urls (symbol, company_name, tradingview_logoid)) {
            try {
                var message = new Soup.Message ("GET", url);
                message.request_headers.append ("User-Agent", "Mozilla/5.0 (dockx widlet)");
                message.request_headers.append ("Accept", "image/*,*/*;q=0.8");

                var bytes = yield soup_session.send_and_read_async (message, Priority.DEFAULT, null);
                if (message.status_code != Soup.Status.OK) {
                    continue;
                }

                var texture = Gdk.Texture.from_bytes (bytes);
                logo_cache.insert (symbol, texture);
                save_logo_to_disk (symbol, bytes);

                if (request_serial == logo_request_serial && symbol == current_symbol) {
                    logo_image.paintable = texture;
                    logo_stack.visible_child_name = "logo";
                }

                return;
            } catch (Error e) {
                debug ("Couldn't download stock logo '%s': %s", url, e.message);
            }
        }

        if (request_serial == logo_request_serial && symbol == current_symbol) {
            logo_stack.visible_child_name = "fallback";
        }
    }

    private bool load_logo_from_disk (string symbol, out Gdk.Texture? texture) {
        texture = null;

        var cache_path = get_logo_cache_path (symbol);
        if (!FileUtils.test (cache_path, FileTest.EXISTS)) {
            return false;
        }

        try {
            uint8[] raw_data;
            FileUtils.get_data (cache_path, out raw_data);
            var bytes = new Bytes (raw_data);
            texture = Gdk.Texture.from_bytes (bytes);
            return texture != null;
        } catch (Error e) {
            debug ("Could not load stock logo cache '%s': %s", cache_path, e.message);
            return false;
        }
    }

    private void save_logo_to_disk (string symbol, Bytes bytes) {
        var cache_path = get_logo_cache_path (symbol);
        try {
            unowned uint8[] raw_data = bytes.get_data ();
            FileUtils.set_data (cache_path, raw_data);
        } catch (Error e) {
            debug ("Could not save stock logo cache '%s': %s", cache_path, e.message);
        }
    }

    private string get_logo_cache_path (string symbol) {
        var key = sanitize_symbol (symbol).down ();
        if (key == "") {
            key = "unknown";
        }

        try {
            var non_alnum = new Regex ("[^a-z0-9]+");
            key = non_alnum.replace (key, -1, 0, "_");
        } catch (Error e) {
            warning ("Could not sanitize stock logo cache key '%s': %s", symbol, e.message);
        }

        return Path.build_filename (logo_disk_cache_dir, "%s.logo".printf (key));
    }

    private async string resolve_tradingview_logoid (string symbol) {
        var cleaned_symbol = sanitize_symbol (symbol);
        if (cleaned_symbol == "") {
            return "";
        }

        var cached = tradingview_logoid_cache.lookup (cleaned_symbol);
        if (cached != null) {
            return cached;
        }

        if (soup_session == null) {
            soup_session = new Soup.Session () {
                timeout = 10
            };
        }

        var payload = "{\"filter\":[{\"left\":\"name\",\"operation\":\"equal\",\"right\":\"%s\"}],\"columns\":[\"logoid\"],\"range\":[0,1]}".printf (cleaned_symbol);

        try {
            var message = new Soup.Message ("POST", "https://scanner.tradingview.com/america/scan");
            message.request_headers.append ("User-Agent", "Mozilla/5.0 (dockx widlet)");
            message.request_headers.append ("Accept", "application/json");
            message.set_request_body_from_bytes ("application/json", new Bytes ((uint8[]) payload.data));

            var bytes = yield soup_session.send_and_read_async (message, Priority.DEFAULT, null);
            if (message.status_code != Soup.Status.OK) {
                return "";
            }

            var response = (string) bytes.get_data ();
            string parsed_logoid;
            if (!parse_tradingview_logoid (response, out parsed_logoid)) {
                return "";
            }

            if (parsed_logoid != "") {
                tradingview_logoid_cache.insert (cleaned_symbol, parsed_logoid);
                return parsed_logoid;
            }
        } catch (Error e) {
            debug ("Could not resolve TradingView logoid for %s: %s", cleaned_symbol, e.message);
        }

        return "";
    }

    private static bool parse_tradingview_logoid (string payload, out string logoid) {
        logoid = "";

        try {
            var regex = new Regex ("\"d\"\\s*:\\s*\\[\\s*\"([^\"]+)\"");
            MatchInfo info;
            if (!regex.match (payload, 0, out info)) {
                return false;
            }

            logoid = info.fetch (1).strip ();
            return logoid != "";
        } catch (Error e) {
            warning ("Could not parse TradingView logoid: %s", e.message);
            return false;
        }
    }

    private static string[] get_logo_urls (string symbol, string company_name, string tradingview_logoid) {
        string[] urls = {};

        if (tradingview_logoid.strip () != "") {
            urls += "https://s3-symbol-logo.tradingview.com/%s.svg".printf (Uri.escape_string (tradingview_logoid, null, false));
        }

        foreach (var slug in build_tradingview_logo_slugs (symbol, company_name)) {
            urls += "https://s3-symbol-logo.tradingview.com/%s.svg".printf (Uri.escape_string (slug, null, false));
        }

        var cleaned = sanitize_symbol (symbol);
        if (cleaned == "") {
            return urls;
        }

        string[] variants = {};
        variants += cleaned;

        var dash_variant = cleaned.replace (".", "-");
        if (dash_variant != cleaned) {
            variants += dash_variant;
        }

        var plain_variant = cleaned.replace (".", "");
        if (plain_variant != cleaned && plain_variant != dash_variant) {
            variants += plain_variant;
        }

        foreach (var variant in variants) {
            var escaped = Uri.escape_string (variant, null, false);
            urls += "https://financialmodelingprep.com/image-stock/%s.png".printf (escaped);
            urls += "https://eodhd.com/img/logos/US/%s.png".printf (escaped);
        }

        return urls;
    }

    private static string[] build_tradingview_logo_slugs (string symbol, string company_name) {
        string[] slugs = {};

        var cleaned_symbol = sanitize_symbol (symbol).down ();
        if (cleaned_symbol != "") {
            slugs = append_unique_slug (slugs, cleaned_symbol);
        }

        var words = extract_company_logo_words (company_name);
        if (words.length > 0) {
            slugs = append_unique_slug (slugs, join_slug_words (words));

            if (words.length >= 2) {
                slugs = append_unique_slug (slugs, join_slug_words (words[0:2]));
            }

            slugs = append_unique_slug (slugs, words[0]);
        }

        return slugs;
    }

    private static string[] extract_company_logo_words (string company_name) {
        if (company_name.strip () == "") {
            return {};
        }

        var normalized = company_name.down ();
        normalized = normalized.replace ("&", " and ");

        try {
            var non_alnum = new Regex ("[^a-z0-9]+");
            normalized = non_alnum.replace (normalized, -1, 0, " ");
        } catch (Error e) {
            warning ("Could not normalize company name '%s': %s", company_name, e.message);
        }

        string[] words = {};
        foreach (var token in normalized.split (" ")) {
            var word = token.strip ();
            if (word == "" || is_company_stopword (word)) {
                continue;
            }

            words += word;
        }

        return words;
    }

    private static bool is_company_stopword (string word) {
        switch (word) {
            case "inc":
            case "incorporated":
            case "corp":
            case "corporation":
            case "co":
            case "company":
            case "limited":
            case "ltd":
            case "plc":
            case "sa":
            case "nv":
            case "ag":
            case "holdings":
            case "holding":
            case "group":
            case "class":
            case "common":
            case "stock":
            case "adr":
            case "the":
            case "series":
            case "ordinary":
                return true;
            default:
                return false;
        }
    }

    private static string join_slug_words (string[] words) {
        var slug = string.joinv ("-", words);
        return slug.strip ();
    }

    private static string[] append_unique_slug (string[] values, string value) {
        var cleaned = value.strip ();
        if (cleaned == "") {
            return values;
        }

        foreach (var existing in values) {
            if (existing == cleaned) {
                return values;
            }
        }

        string[] updated = {};
        foreach (var existing in values) {
            updated += existing;
        }
        updated += cleaned;

        return updated;
    }

    private void draw_sparkline (Cairo.Context cr, int width, int height) {
        if (width <= 2 || height <= 2) {
            return;
        }

        double line_red;
        double line_green;
        double line_blue;
        get_line_color (out line_red, out line_green, out line_blue);

        if (current_trend_values.length < 2) {
            var baseline = height * 0.58;
            cr.set_source_rgba (line_red, line_green, line_blue, 0.88);
            cr.set_line_width (1.4);
            cr.move_to (0, baseline);
            cr.line_to (width - 1, baseline);
            cr.stroke ();
            return;
        }

        trace_sparkline_path (cr, width, height, current_trend_values);
        cr.line_to (width - 1, height - 1);
        cr.line_to (0, height - 1);
        cr.close_path ();

        var fill_pattern = new Cairo.Pattern.linear (0, 0, 0, height);
        fill_pattern.add_color_stop_rgba (0.0, line_red, line_green, line_blue, 0.22);
        fill_pattern.add_color_stop_rgba (1.0, line_red, line_green, line_blue, 0.02);
        cr.set_source (fill_pattern);
        cr.fill ();

        trace_sparkline_path (cr, width, height, current_trend_values);
        cr.set_source_rgba (line_red, line_green, line_blue, 0.34);
        cr.set_line_width (3.3);
        cr.stroke ();

        trace_sparkline_path (cr, width, height, current_trend_values);
        cr.set_source_rgba (line_red, line_green, line_blue, 0.96);
        cr.set_line_width (1.45);
        cr.stroke ();
    }

    private static void trace_sparkline_path (Cairo.Context cr, int width, int height, double[] raw_values) {
        var values = normalize_trend_values (raw_values);
        if (values.length == 0) {
            return;
        }

        double min_value = values[0];
        double max_value = values[0];
        foreach (var value in values) {
            if (value < min_value) {
                min_value = value;
            }
            if (value > max_value) {
                max_value = value;
            }
        }

        var range = max_value - min_value;
        if (Math.fabs (range) < 0.0001) {
            range = 1.0;
            min_value -= 0.5;
            max_value += 0.5;
        }

        var chart_top = 1.0;
        var chart_bottom = (double) (height - 2);
        var chart_height = chart_bottom - chart_top;
        var total_points = values.length;

        for (int i = 0; i < total_points; i++) {
            var x = ((double) i / (double) (total_points - 1)) * (double) (width - 1);
            var normalized = (values[i] - min_value) / range;
            var y = chart_bottom - (normalized * chart_height);

            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
    }

    private static double[] normalize_trend_values (double[] source) {
        if (source.length <= 32) {
            return source;
        }

        const int target_points = 32;
        var step = (double) (source.length - 1) / (double) (target_points - 1);

        double[] normalized = {};
        for (int i = 0; i < target_points; i++) {
            var index = (int) Math.round (i * step);
            if (index < 0) {
                index = 0;
            } else if (index >= source.length) {
                index = source.length - 1;
            }

            normalized += source[index];
        }

        return normalized;
    }

    private void get_line_color (out double red, out double green, out double blue) {
        red = 0.56;
        green = 0.77;
        blue = 1.0;

        if (current_change_percent > 0.001) {
            red = 0.0;
            green = 1.0;
            blue = 0.36;
        } else if (current_change_percent < -0.001) {
            red = 1.0;
            green = 0.1;
            blue = 0.2;
        }
    }

    private void set_trend_classes (double change_percent) {
        var trend_class = "stock-trend-neutral";
        var change_class = "stock-change-neutral";

        if (change_percent > 0.001) {
            trend_class = "stock-trend-up";
            change_class = "stock-change-up";
        } else if (change_percent < -0.001) {
            trend_class = "stock-trend-down";
            change_class = "stock-change-down";
        }

        if (current_trend_css_class != "") {
            remove_css_class (current_trend_css_class);
        }
        if (current_change_css_class != "") {
            change_label.remove_css_class (current_change_css_class);
        }

        current_trend_css_class = trend_class;
        current_change_css_class = change_class;

        add_css_class (current_trend_css_class);
        change_label.add_css_class (current_change_css_class);
    }

    private void update_symbol_labels () {
        if (symbols.length == 0) {
            symbol_label.label = "--";
            company_label.label = _("No symbols");
            logo_fallback_label.label = "S";
            logo_stack.visible_child_name = "fallback";
            return;
        }

        current_symbol = symbols[current_symbol_index];
        symbol_label.label = current_symbol;
        logo_fallback_label.label = symbol_to_badge (current_symbol);
    }

    private void refresh_details_labels () {
        details_symbol_value_label.label = current_symbol != "" ? current_symbol : "--";
        details_company_value_label.label = current_company != "" ? current_company : "--";
        details_price_value_label.label = has_current_data ? format_price (current_price, current_currency) : "--";
        details_change_value_label.label = has_current_data ? format_percent (current_change_percent) : "--";

        if (has_current_data && current_day_low > 0 && current_day_high > 0) {
            details_day_range_value_label.label = "%s - %s".printf (
                format_price (current_day_low, current_currency),
                format_price (current_day_high, current_currency)
            );
        } else {
            details_day_range_value_label.label = "--";
        }

        details_prev_close_value_label.label = has_current_data && current_previous_close > 0
            ? format_price (current_previous_close, current_currency)
            : "--";

        details_volume_value_label.label = has_current_data && current_volume > 0
            ? format_volume (current_volume)
            : "--";
    }

    private static string symbol_to_badge (string symbol) {
        var cleaned = symbol.strip ();
        if (cleaned == "") {
            return "S";
        }

        return cleaned.substring (0, 1);
    }

    private static string format_price (double price, string currency) {
        var symbol = "$";
        switch (currency.up ()) {
            case "EUR":
                symbol = "€";
                break;
            case "GBP":
                symbol = "£";
                break;
            case "JPY":
                symbol = "¥";
                break;
            case "USD":
            default:
                symbol = "$";
                break;
        }

        return "%s%s".printf (symbol, to_decimal_comma (price));
    }

    private static string format_percent (double value) {
        if (value > 0.001) {
            return "+ %s%%".printf (to_decimal_comma (Math.fabs (value)));
        }

        if (value < -0.001) {
            return "- %s%%".printf (to_decimal_comma (Math.fabs (value)));
        }

        return "0,00%";
    }

    private static string to_decimal_comma (double value) {
        return "%.2f".printf (value).replace (".", ",");
    }

    private static string format_volume (int64 volume) {
        if (volume >= 1000000000) {
            return "%.2fB".printf ((double) volume / 1000000000.0);
        }
        if (volume >= 1000000) {
            return "%.2fM".printf ((double) volume / 1000000.0);
        }
        if (volume >= 1000) {
            return "%.2fK".printf ((double) volume / 1000.0);
        }

        return volume.to_string ();
    }

    private void update_size_variant () {
        if (card_overlay == null) {
            return;
        }

        // Keep stock card height locked to dock icon size so medium is exactly 48px.
        card_overlay.height_request = icon_size;
    }

    private static int64 get_unix_seconds () {
        return (int64) (GLib.get_real_time () / 1000000);
    }

    private static bool parse_double_field (string payload, string key, out double value) {
        value = 0;

        try {
            var pattern = "\"%s\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?)".printf (Regex.escape_string (key));
            var regex = new Regex (pattern);
            MatchInfo info;
            if (!regex.match (payload, 0, out info)) {
                return false;
            }

            value = double.parse (info.fetch (1));
            return true;
        } catch (Error e) {
            warning ("Could not parse double field '%s': %s", key, e.message);
            return false;
        }
    }

    private static bool parse_nullable_double_array_field (string payload, string key, out double[] values) {
        values = {};

        try {
            var pattern = "\"%s\"\\s*:\\s*\\[([^\\]]*)\\]".printf (Regex.escape_string (key));
            var regex = new Regex (pattern);
            MatchInfo info;
            if (!regex.match (payload, 0, out info)) {
                return false;
            }

            var content = info.fetch (1).strip ();
            if (content == "") {
                return true;
            }

            double[] parsed_values = {};
            foreach (var piece in content.split (",")) {
                var token = piece.strip ();
                if (token == "" || token == "null") {
                    continue;
                }

                parsed_values += double.parse (token);
            }

            values = parsed_values;
            return true;
        } catch (Error e) {
            warning ("Could not parse nullable array field '%s': %s", key, e.message);
            return false;
        }
    }

    private static bool parse_string_field (string payload, string key, out string value) {
        value = "";

        try {
            var pattern = "\"%s\"\\s*:\\s*\"([^\"]+)\"".printf (Regex.escape_string (key));
            var regex = new Regex (pattern);
            MatchInfo info;
            if (!regex.match (payload, 0, out info)) {
                return false;
            }

            value = info.fetch (1);
            return true;
        } catch (Error e) {
            warning ("Could not parse string field '%s': %s", key, e.message);
            return false;
        }
    }
}
