/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.WeatherWidletItem : ContainerItem {
    private const string LOCATION_KEY = "widlet-weather-location";
    private const string LATITUDE_KEY = "widlet-weather-latitude";
    private const string LONGITUDE_KEY = "widlet-weather-longitude";
    private const string UNIT_KEY = "widlet-weather-unit";
    private const string MINIMAL_MODE_KEY = "widlet-weather-minimal-mode";
    private const string SIM_ENABLED_KEY = "widlet-weather-sim-enabled";
    private const string SIM_WEATHER_CODE_KEY = "widlet-weather-sim-weather-code";
    private const string SIM_TEMPERATURE_KEY = "widlet-weather-sim-temperature";
    private const string SIM_HOUR_KEY = "widlet-weather-sim-hour";

    private const int CARD_WIDTH = 160;
    private const int CARD_OUTER_WIDTH = CARD_WIDTH + Launcher.PADDING * 2;
    private const int FULL_MARGIN_START = 10;
    private const int FULL_MARGIN_END = 4;
    private const int FULL_MARGIN_TOP = 2;
    private const int FULL_MARGIN_BOTTOM = 2;
    private const int FULL_RIGHT_RESERVE_WIDTH = 58;
    private const int FULL_ICON_PIXEL_SIZE = 54;
    private const int MINIMAL_ICON_PIXEL_SIZE = 46;
    private const uint REFRESH_INTERVAL_SECONDS = 900;
    private const int FORECAST_DAYS_TO_SHOW = 5;
    private const int FORECAST_FETCH_DAYS = FORECAST_DAYS_TO_SHOW + 1;

    private static Soup.Session soup_session;

    private class ForecastPopover : Gtk.Popover {
        class construct {
            set_css_name ("tooltip");
        }
    }

    public signal void mode_changed ();
    public bool minimal_mode { get; set; default = false; }

    private Gtk.Label condition_label;
    private Gtk.Label city_label;
    private Gtk.Label temperature_label;
    private Gtk.Label temperature_degree_dot;
    private Gtk.Label temperature_negative_sign;
    private Gtk.Image weather_icon;
    private Gtk.Label forecast_location_label;
    private Gtk.Label forecast_status_label;
    private Gtk.Box forecast_rows_box;
    private Gtk.Box left_box;
    private Gtk.Box right_reserve;
    private Gtk.Box base_content;
    private Gtk.Box temperature_overlay;

    private uint refresh_timeout_id = 0;
    private bool refresh_in_progress = false;
    private bool has_temperature_value = false;
    private int current_temperature_value = 0;
    private uint forecast_request_serial = 0;
    private string current_period_css_class = "";
    private string current_cloud_css_class = "";

    public WeatherWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    protected override int get_width_for_icon_size (int icon_size) {
        return minimal_mode ? icon_size : CARD_WIDTH;
    }

    public int get_dock_width () {
        return minimal_mode ? ItemManager.get_launcher_size () : CARD_OUTER_WIDTH;
    }

    construct {
        if (soup_session == null) {
            soup_session = new Soup.Session () {
                timeout = 10
            };
        }

        add_css_class ("weather-widlet-item");

        condition_label = new Gtk.Label (_("Loading weather...")) {
            xalign = 0,
            single_line_mode = true,
            ellipsize = Pango.EllipsizeMode.END,
            hexpand = true
        };
        condition_label.add_css_class ("weather-widlet-condition");

        city_label = new Gtk.Label ("") {
            xalign = 0,
            single_line_mode = true,
            ellipsize = Pango.EllipsizeMode.END,
            hexpand = true
        };
        city_label.add_css_class ("weather-widlet-city");

        left_box = new Gtk.Box (VERTICAL, 0) {
            hexpand = true,
            valign = CENTER
        };
        left_box.append (condition_label);
        left_box.append (city_label);

        temperature_label = new Gtk.Label ("--°") {
            xalign = 1,
            halign = END,
            valign = CENTER
        };
        temperature_label.add_css_class ("weather-widlet-temperature");

        temperature_degree_dot = new Gtk.Label ("°") {
            halign = END,
            valign = START,
            visible = false,
            can_target = false
        };
        temperature_degree_dot.add_css_class ("weather-widlet-degree-dot");

        temperature_negative_sign = new Gtk.Label ("−") {
            halign = START,
            valign = CENTER,
            visible = false,
            can_target = false
        };
        temperature_negative_sign.add_css_class ("weather-widlet-negative-sign");

        var temperature_value_overlay = new Gtk.Overlay () {
            child = temperature_label,
            can_target = false
        };
        temperature_value_overlay.add_overlay (temperature_negative_sign);
        temperature_value_overlay.set_measure_overlay (temperature_negative_sign, false);
        temperature_value_overlay.add_overlay (temperature_degree_dot);
        temperature_value_overlay.set_measure_overlay (temperature_degree_dot, false);

        weather_icon = new Gtk.Image.from_resource ("/io/elementary/dock/weather-icons/not-available.png") {
            pixel_size = FULL_ICON_PIXEL_SIZE,
            halign = END,
            valign = END,
            can_target = false
        };
        weather_icon.add_css_class ("weather-widlet-icon");

        right_reserve = new Gtk.Box (HORIZONTAL, 0) {
            halign = END,
            valign = CENTER,
            width_request = FULL_RIGHT_RESERVE_WIDTH
        };

        base_content = new Gtk.Box (HORIZONTAL, 4) {
            margin_start = FULL_MARGIN_START,
            margin_end = FULL_MARGIN_END,
            margin_top = FULL_MARGIN_TOP,
            margin_bottom = FULL_MARGIN_BOTTOM
        };
        base_content.append (left_box);
        base_content.append (right_reserve);

        temperature_overlay = new Gtk.Box (HORIZONTAL, 0) {
            halign = END,
            valign = CENTER,
            can_target = false
        };
        temperature_overlay.append (temperature_value_overlay);

        var content = new Gtk.Overlay () {
            child = base_content,
            overflow = HIDDEN
        };
        content.add_css_class ("weather-widlet-content");
        content.add_overlay (weather_icon);
        content.add_overlay (temperature_overlay);

        child = content;

        var forecast_title_label = new Gtk.Label (_("Forecast")) {
            xalign = 0
        };
        forecast_title_label.add_css_class ("weather-forecast-title");

        forecast_location_label = new Gtk.Label ("") {
            xalign = 0,
            single_line_mode = true,
            ellipsize = Pango.EllipsizeMode.END
        };
        forecast_location_label.add_css_class ("weather-forecast-location");

        forecast_rows_box = new Gtk.Box (VERTICAL, 6);

        forecast_status_label = new Gtk.Label (_("Loading forecast...")) {
            xalign = 0,
            wrap = true
        };
        forecast_status_label.add_css_class (Granite.CssClass.DIM);
        forecast_status_label.add_css_class (Granite.CssClass.SMALL);
        forecast_status_label.add_css_class ("weather-forecast-status");

        var forecast_content = new Gtk.Box (VERTICAL, 8) {
            margin_start = 10,
            margin_end = 10,
            margin_top = 8,
            margin_bottom = 8,
            width_request = 260
        };
        forecast_content.add_css_class ("weather-forecast-popover");
        forecast_content.append (forecast_title_label);
        forecast_content.append (forecast_location_label);
        forecast_content.append (new Gtk.Separator (HORIZONTAL));
        forecast_content.append (forecast_rows_box);
        forecast_content.append (forecast_status_label);

        popover_menu = new ForecastPopover () {
            autohide = true,
            position = TOP,
            has_arrow = false,
            child = forecast_content
        };
        popover_menu.set_offset (0, -1);
        popover_menu.set_parent (this);

        gesture_click.button = 0;
        gesture_click.released.connect (on_click_released);

        update_city_label ();
        tooltip_text = "%s\n%s %s".printf (condition_label.label, city_label.label, temperature_label.label);

        if (dock_settings.settings_schema.has_key (LOCATION_KEY)) {
            dock_settings.changed[LOCATION_KEY].connect (() => {
                update_city_label ();
                tooltip_text = "%s\n%s %s".printf (condition_label.label, city_label.label, temperature_label.label);
            });
        }

        if (dock_settings.settings_schema.has_key (LATITUDE_KEY)) {
            dock_settings.changed[LATITUDE_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (LONGITUDE_KEY)) {
            dock_settings.changed[LONGITUDE_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (UNIT_KEY)) {
            dock_settings.changed[UNIT_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (SIM_ENABLED_KEY)) {
            dock_settings.changed[SIM_ENABLED_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (SIM_WEATHER_CODE_KEY)) {
            dock_settings.changed[SIM_WEATHER_CODE_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (SIM_TEMPERATURE_KEY)) {
            dock_settings.changed[SIM_TEMPERATURE_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (SIM_HOUR_KEY)) {
            dock_settings.changed[SIM_HOUR_KEY].connect (() => refresh_weather.begin ());
        }
        if (dock_settings.settings_schema.has_key (MINIMAL_MODE_KEY)) {
            dock_settings.bind (MINIMAL_MODE_KEY, this, "minimal-mode", DEFAULT);
        }

        notify["minimal-mode"].connect (apply_mode);
        apply_mode ();

        refresh_weather.begin ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_weather.begin ();
            return Source.CONTINUE;
        });
    }

    ~WeatherWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }

        popover_menu.unparent ();
        popover_menu.dispose ();
    }

    private void apply_mode () {
        if (minimal_mode) {
            add_css_class ("minimal");
            left_box.visible = false;
            right_reserve.width_request = 0;
            base_content.margin_start = 0;
            base_content.margin_end = 0;
            base_content.margin_top = 0;
            base_content.margin_bottom = 0;
            weather_icon.pixel_size = MINIMAL_ICON_PIXEL_SIZE;
            temperature_overlay.halign = CENTER;
            temperature_label.halign = CENTER;
            temperature_label.xalign = 0.5f;
        } else {
            remove_css_class ("minimal");
            left_box.visible = true;
            right_reserve.width_request = FULL_RIGHT_RESERVE_WIDTH;
            base_content.margin_start = FULL_MARGIN_START;
            base_content.margin_end = FULL_MARGIN_END;
            base_content.margin_top = FULL_MARGIN_TOP;
            base_content.margin_bottom = FULL_MARGIN_BOTTOM;
            weather_icon.pixel_size = FULL_ICON_PIXEL_SIZE;
            temperature_overlay.halign = END;
            temperature_label.halign = END;
            temperature_label.xalign = 1f;
        }

        // Refresh width-request binding transform on ContainerItem.
        update_temperature_label ();
        notify_property ("icon-size");
        queue_resize ();
        mode_changed ();
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

        popover_tooltip.popdown ();
        forecast_location_label.label = city_label.label;
        popover_menu.popup ();
        refresh_forecast.begin ();
    }

    private async void refresh_forecast () {
        var request_serial = ++forecast_request_serial;
        clear_forecast_rows ();
        forecast_status_label.label = _("Loading forecast...");
        forecast_status_label.visible = true;

        try {
            var unit_symbol = get_temperature_unit () == "fahrenheit" ? "F" : "C";

            if (is_simulation_enabled ()) {
                var simulated_code = get_int_setting_or_default (SIM_WEATHER_CODE_KEY, 3);
                var simulated_temp = (int) Math.round (get_double_setting_or_default (SIM_TEMPERATURE_KEY, 21.0));
                for (var i = 0; i < FORECAST_DAYS_TO_SHOW; i++) {
                    var label = i == 0 ? _("Today") : _("Day %d").printf (i + 1);
                    var row = create_forecast_row (
                        label,
                        weather_code_to_label (simulated_code),
                        weather_code_to_resource (simulated_code, true),
                        simulated_temp + 2,
                        simulated_temp - 2,
                        unit_symbol
                    );
                    forecast_rows_box.append (row);
                }
            } else {
                var latitude = dock_settings.get_double (LATITUDE_KEY);
                var longitude = dock_settings.get_double (LONGITUDE_KEY);
                var temperature_unit = get_temperature_unit ();

                var url = "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&daily=weather_code,temperature_2m_max,temperature_2m_min&temperature_unit=%s&timezone=auto&forecast_days=%d".printf (
                    latitude.to_string (),
                    longitude.to_string (),
                    temperature_unit,
                    FORECAST_FETCH_DAYS
                );

                var message = new Soup.Message ("GET", url);
                var bytes = yield soup_session.send_and_read_async (message, Priority.DEFAULT, null);
                if (message.status_code != Soup.Status.OK) {
                    throw new IOError.FAILED ("Unexpected forecast response HTTP %u".printf (message.status_code));
                }

                var body = (string) bytes.get_data ();

                string[] daily_times = {};
                int[] daily_codes = {};
                double[] daily_max_values = {};
                double[] daily_min_values = {};

                if (!parse_string_array_field (body, "time", out daily_times) ||
                    !parse_int_array_field (body, "weather_code", out daily_codes) ||
                    !parse_double_array_field (body, "temperature_2m_max", out daily_max_values) ||
                    !parse_double_array_field (body, "temperature_2m_min", out daily_min_values)) {
                    throw new IOError.FAILED ("Missing daily forecast values in weather response");
                }

                var available = int.min (daily_times.length,
                    int.min (daily_codes.length,
                    int.min (daily_max_values.length, daily_min_values.length)));

                if (available <= 0) {
                    throw new IOError.FAILED ("No daily forecast rows in weather response");
                }

                // Prefer upcoming days; skip today's row when possible.
                var start_index = available > 1 ? 1 : 0;
                var end_index = int.min (available, start_index + FORECAST_DAYS_TO_SHOW);

                for (var i = start_index; i < end_index; i++) {
                    var row = create_forecast_row (
                        format_forecast_day_label (daily_times[i]),
                        weather_code_to_label (daily_codes[i]),
                        weather_code_to_resource (daily_codes[i], true),
                        (int) Math.round (daily_max_values[i]),
                        (int) Math.round (daily_min_values[i]),
                        unit_symbol
                    );
                    forecast_rows_box.append (row);
                }
            }

            if (request_serial != forecast_request_serial) {
                return;
            }

            forecast_status_label.visible = forecast_rows_box.get_first_child () == null;
            if (forecast_status_label.visible) {
                forecast_status_label.label = _("Forecast unavailable");
            }
        } catch (Error e) {
            if (request_serial != forecast_request_serial) {
                return;
            }

            warning ("Failed to load weather forecast: %s", e.message);
            forecast_status_label.label = _("Forecast unavailable");
            forecast_status_label.visible = true;
        }
    }

    private void clear_forecast_rows () {
        Gtk.Widget? child = forecast_rows_box.get_first_child ();
        while (child != null) {
            var next_child = child.get_next_sibling ();
            forecast_rows_box.remove (child);
            child = next_child;
        }
    }

    private Gtk.Widget create_forecast_row (
        string day_label,
        string condition,
        string icon_resource,
        int max_temperature,
        int min_temperature,
        string unit_symbol
    ) {
        var row = new Gtk.Box (HORIZONTAL, 8);
        row.add_css_class ("weather-forecast-row");

        var day = new Gtk.Label (day_label) {
            xalign = 0,
            width_chars = 7
        };
        day.add_css_class ("weather-forecast-day");

        var icon = new Gtk.Image.from_resource (icon_resource) {
            pixel_size = 18,
            halign = CENTER,
            valign = CENTER
        };
        icon.add_css_class ("weather-forecast-icon");

        var condition_label = new Gtk.Label (condition) {
            xalign = 0,
            hexpand = true,
            single_line_mode = true,
            ellipsize = Pango.EllipsizeMode.END
        };
        condition_label.add_css_class ("weather-forecast-condition");

        var temperatures = new Gtk.Label ("%d°%s / %d°%s".printf (max_temperature, unit_symbol, min_temperature, unit_symbol)) {
            xalign = 1
        };
        temperatures.add_css_class ("weather-forecast-temps");

        row.append (day);
        row.append (icon);
        row.append (condition_label);
        row.append (temperatures);
        return row;
    }

    private static string format_forecast_day_label (string iso_day) {
        var date_time = new DateTime.from_iso8601 ("%sT00:00:00".printf (iso_day), new TimeZone.local ());
        if (date_time != null) {
            return date_time.format ("%a %d");
        }

        return iso_day;
    }

    private async void refresh_weather () {
        if (refresh_in_progress) {
            return;
        }

        refresh_in_progress = true;

        try {
            if (is_simulation_enabled ()) {
                apply_simulated_weather ();
                refresh_in_progress = false;
                return;
            }

            remove_css_class ("weather-preview-mode");

            var latitude = dock_settings.get_double (LATITUDE_KEY);
            var longitude = dock_settings.get_double (LONGITUDE_KEY);
            var temperature_unit = get_temperature_unit ();

            var url = "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code,is_day&temperature_unit=%s&timezone=auto".printf (
                latitude.to_string (),
                longitude.to_string (),
                temperature_unit
            );

            var message = new Soup.Message ("GET", url);
            var bytes = yield soup_session.send_and_read_async (message, Priority.DEFAULT, null);

            if (message.status_code != Soup.Status.OK) {
                throw new IOError.FAILED ("Unexpected weather response HTTP %u".printf (message.status_code));
            }

            var body = (string) bytes.get_data ();

            double temperature_value;
            int weather_code;
            bool is_day;
            var hour = get_local_hour ();

            if (!parse_double_field (body, "temperature_2m", out temperature_value)) {
                throw new IOError.FAILED ("Missing temperature_2m in weather response");
            }

            if (!parse_int_field (body, "weather_code", out weather_code)) {
                throw new IOError.FAILED ("Missing weather_code in weather response");
            }

            int is_day_int;
            if (!parse_int_field (body, "is_day", out is_day_int)) {
                throw new IOError.FAILED ("Missing is_day in weather response");
            }
            is_day = is_day_int == 1;

            string current_time;
            if (parse_string_field (body, "time", out current_time)) {
                int parsed_hour;
                if (parse_hour_from_timestamp (current_time, out parsed_hour)) {
                    hour = parsed_hour;
                }
            }

            apply_weather_state (weather_code, temperature_value, is_day, hour, false);
        } catch (Error e) {
            warning ("Failed to update weather widlet: %s", e.message);
            condition_label.label = _("Weather unavailable");
            has_temperature_value = false;
            update_temperature_label ();
            weather_icon.set_from_resource ("/io/elementary/dock/weather-icons/not-available.png");
            tooltip_text = "%s\n%s %s".printf (condition_label.label, city_label.label, temperature_label.label);
            apply_weather_style_classes (3, get_local_hour ());
        }

        refresh_in_progress = false;
    }

    private void apply_simulated_weather () {
        add_css_class ("weather-preview-mode");

        var weather_code = get_int_setting_or_default (SIM_WEATHER_CODE_KEY, 3);
        var temperature_value = get_double_setting_or_default (SIM_TEMPERATURE_KEY, 21.0);
        var hour = clamp_hour (get_int_setting_or_default (SIM_HOUR_KEY, get_local_hour ()));
        var is_day = hour >= 6 && hour < 20;

        apply_weather_state (weather_code, temperature_value, is_day, hour, true);
    }

    private void apply_weather_state (int weather_code, double temperature_value, bool is_day, int hour, bool simulated) {
        var condition = weather_code_to_label (weather_code);
        var icon_resource = weather_code_to_resource (weather_code, is_day);
        var temperature = (int) Math.round (temperature_value);
        var unit_symbol = get_temperature_unit () == "fahrenheit" ? "F" : "C";

        condition_label.label = condition;
        has_temperature_value = true;
        current_temperature_value = temperature;
        update_temperature_label ();
        weather_icon.set_from_resource (icon_resource);
        apply_weather_style_classes (weather_code, hour);

        if (simulated) {
            tooltip_text = "%s\n%s %d°%s · %s".printf (condition, city_label.label, temperature, unit_symbol, _("Preview mode"));
        } else {
            tooltip_text = "%s\n%s %d°%s".printf (condition, city_label.label, temperature, unit_symbol);
        }
    }

    private void apply_weather_style_classes (int weather_code, int hour) {
        var period_css_class = get_period_css_class (hour);
        var cloud_css_class = get_cloud_css_class (weather_code);

        if (current_period_css_class != "") {
            remove_css_class (current_period_css_class);
        }
        if (current_cloud_css_class != "") {
            remove_css_class (current_cloud_css_class);
        }

        current_period_css_class = period_css_class;
        current_cloud_css_class = cloud_css_class;

        add_css_class (current_period_css_class);
        add_css_class (current_cloud_css_class);
    }

    private void update_city_label () {
        if (!dock_settings.settings_schema.has_key (LOCATION_KEY)) {
            city_label.label = _("Unknown location");
            forecast_location_label.label = city_label.label;
            return;
        }

        var location = dock_settings.get_string (LOCATION_KEY).strip ();
        city_label.label = extract_primary_location_name (location);
        forecast_location_label.label = city_label.label;
    }

    private void update_temperature_label () {
        if (!has_temperature_value) {
            temperature_label.label = minimal_mode ? "--" : "--°";
            temperature_degree_dot.visible = false;
            temperature_negative_sign.visible = false;
            return;
        }

        if (minimal_mode) {
            var absolute_temperature = current_temperature_value < 0
                ? -current_temperature_value
                : current_temperature_value;

            temperature_label.label = "%d".printf (absolute_temperature);
            temperature_degree_dot.visible = true;
            temperature_negative_sign.visible = current_temperature_value < 0;
        } else {
            temperature_label.label = "%d°".printf (current_temperature_value);
            temperature_degree_dot.visible = false;
            temperature_negative_sign.visible = false;
        }
    }

    private static string extract_primary_location_name (string location) {
        var trimmed_location = location.strip ();
        if (trimmed_location == "") {
            return _("Unknown location");
        }

        var comma_index = trimmed_location.index_of (",");
        if (comma_index <= 0) {
            return trimmed_location;
        }

        return trimmed_location.substring (0, comma_index).strip ();
    }

    private bool is_simulation_enabled () {
        // Hidden for end users: keep weather preview tooling disabled in production.
        return false;
    }

    private string get_temperature_unit () {
        if (!dock_settings.settings_schema.has_key (UNIT_KEY)) {
            return "celsius";
        }

        var configured_unit = dock_settings.get_string (UNIT_KEY).strip ().down ();
        if (configured_unit == "fahrenheit") {
            return "fahrenheit";
        }

        return "celsius";
    }

    private static int get_local_hour () {
        var now = new DateTime.now_local ();
        return now.get_hour ();
    }

    private static int clamp_hour (int hour) {
        if (hour < 0) {
            return 0;
        }
        if (hour > 23) {
            return 23;
        }

        return hour;
    }

    private int get_int_setting_or_default (string key, int fallback) {
        if (!dock_settings.settings_schema.has_key (key)) {
            return fallback;
        }

        return dock_settings.get_int (key);
    }

    private double get_double_setting_or_default (string key, double fallback) {
        if (!dock_settings.settings_schema.has_key (key)) {
            return fallback;
        }

        return dock_settings.get_double (key);
    }

    private static string get_period_css_class (int hour) {
        var normalized_hour = clamp_hour (hour);
        if (normalized_hour >= 5 && normalized_hour <= 7) {
            return "weather-period-dawn";
        }
        if (normalized_hour >= 8 && normalized_hour <= 16) {
            return "weather-period-day";
        }
        if (normalized_hour >= 17 && normalized_hour <= 19) {
            return "weather-period-sunset";
        }

        return "weather-period-night";
    }

    private static string get_cloud_css_class (int weather_code) {
        switch (weather_code) {
            case 0:
                return "weather-cloud-clear";
            case 1:
            case 2:
                return "weather-cloud-partly";
            case 95:
            case 96:
            case 99:
                return "weather-cloud-storm";
            default:
                return "weather-cloud-cloudy";
        }
    }

    private static bool parse_hour_from_timestamp (string timestamp, out int hour) {
        hour = 0;

        try {
            var regex = new Regex ("T([0-9]{2})");
            MatchInfo info;
            if (!regex.match (timestamp, 0, out info)) {
                return false;
            }

            hour = clamp_hour (int.parse (info.fetch (1)));
            return true;
        } catch (Error e) {
            warning ("Could not parse weather hour from '%s': %s", timestamp, e.message);
            return false;
        }
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

    private static bool parse_double_array_field (string payload, string key, out double[] values) {
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
                if (token == "") {
                    continue;
                }

                parsed_values += double.parse (token);
            }

            values = parsed_values;
            return true;
        } catch (Error e) {
            warning ("Could not parse double array field '%s': %s", key, e.message);
            return false;
        }
    }

    private static bool parse_int_field (string payload, string key, out int value) {
        value = 0;

        double parsed;
        if (!parse_double_field (payload, key, out parsed)) {
            return false;
        }

        value = (int) Math.round (parsed);
        return true;
    }

    private static bool parse_int_array_field (string payload, string key, out int[] values) {
        values = {};

        double[] parsed_values;
        if (!parse_double_array_field (payload, key, out parsed_values)) {
            return false;
        }

        int[] parsed_int_values = {};
        foreach (var number in parsed_values) {
            parsed_int_values += (int) Math.round (number);
        }

        values = parsed_int_values;
        return true;
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

    private static bool parse_string_array_field (string payload, string key, out string[] values) {
        values = {};

        try {
            var pattern = "\"%s\"\\s*:\\s*\\[([^\\]]*)\\]".printf (Regex.escape_string (key));
            var regex = new Regex (pattern);
            MatchInfo info;
            if (!regex.match (payload, 0, out info)) {
                return false;
            }

            var content = info.fetch (1);
            if (content.strip () == "") {
                return true;
            }

            var item_regex = new Regex ("\"([^\"]+)\"");
            MatchInfo item_info;
            if (!item_regex.match (content, 0, out item_info)) {
                return true;
            }

            string[] parsed_values = {};
            do {
                parsed_values += item_info.fetch (1);
            } while (item_info.next ());

            values = parsed_values;
            return true;
        } catch (Error e) {
            warning ("Could not parse string array field '%s': %s", key, e.message);
            return false;
        }
    }

    private static string weather_code_to_label (int weather_code) {
        switch (weather_code) {
            case 0:
                return _("Clear sky");
            case 1:
                return _("Mainly clear");
            case 2:
                return _("Partly cloudy");
            case 3:
                return _("Overcast");
            case 45:
                return _("Fog");
            case 48:
                return _("Rime fog");
            case 51:
                return _("Light drizzle");
            case 53:
                return _("Moderate drizzle");
            case 55:
                return _("Dense drizzle");
            case 56:
                return _("Light freezing drizzle");
            case 57:
                return _("Dense freezing drizzle");
            case 61:
                return _("Slight rain");
            case 63:
                return _("Moderate rain");
            case 65:
                return _("Heavy rain");
            case 66:
                return _("Light freezing rain");
            case 67:
                return _("Heavy freezing rain");
            case 71:
                return _("Slight snow");
            case 73:
                return _("Moderate snow");
            case 75:
                return _("Heavy snow");
            case 77:
                return _("Snow grains");
            case 85:
                return _("Slight snow showers");
            case 86:
                return _("Heavy snow showers");
            case 80:
                return _("Slight rain showers");
            case 81:
                return _("Moderate rain showers");
            case 82:
                return _("Violent rain showers");
            case 95:
                return _("Thunderstorm");
            case 96:
                return _("Thunderstorm with slight hail");
            case 99:
                return _("Thunderstorm with heavy hail");
            default:
                return _("Unknown weather");
        }
    }

    private static string weather_code_to_resource (int weather_code, bool is_day) {
        switch (weather_code) {
            case 0:
                return is_day
                    ? "/io/elementary/dock/weather-icons/clear-day.png"
                    : "/io/elementary/dock/weather-icons/clear-night.png";
            case 1:
            case 2:
                return is_day
                    ? "/io/elementary/dock/weather-icons/partly-cloudy-day.png"
                    : "/io/elementary/dock/weather-icons/partly-cloudy-night.png";
            case 3:
                return "/io/elementary/dock/weather-icons/overcast.png";
            case 45:
                return is_day
                    ? "/io/elementary/dock/weather-icons/fog-day.png"
                    : "/io/elementary/dock/weather-icons/fog-night.png";
            case 48:
                return "/io/elementary/dock/weather-icons/fog-dense.png";
            case 51:
                return "/io/elementary/dock/weather-icons/drizzle-light.png";
            case 53:
                return "/io/elementary/dock/weather-icons/drizzle-moderate.png";
            case 55:
                return "/io/elementary/dock/weather-icons/drizzle-heavy.png";
            case 56:
                return is_day
                    ? "/io/elementary/dock/weather-icons/freezing-drizzle-day.png"
                    : "/io/elementary/dock/weather-icons/freezing-drizzle-night.png";
            case 57:
                return "/io/elementary/dock/weather-icons/freezing-rain-heavy.png";
            case 61:
                return "/io/elementary/dock/weather-icons/rain-light.png";
            case 63:
                return "/io/elementary/dock/weather-icons/rain-moderate.png";
            case 65:
                return "/io/elementary/dock/weather-icons/rain-heavy.png";
            case 66:
                return "/io/elementary/dock/weather-icons/freezing-rain-light.png";
            case 67:
                return "/io/elementary/dock/weather-icons/freezing-rain-heavy.png";
            case 71:
                return "/io/elementary/dock/weather-icons/snow-light.png";
            case 73:
                return "/io/elementary/dock/weather-icons/snow-moderate.png";
            case 75:
                return "/io/elementary/dock/weather-icons/snow-heavy.png";
            case 77:
                return "/io/elementary/dock/weather-icons/snow-grains.png";
            case 80:
                return is_day
                    ? "/io/elementary/dock/weather-icons/overcast-day-rain.png"
                    : "/io/elementary/dock/weather-icons/overcast-night-rain.png";
            case 81:
                return is_day
                    ? "/io/elementary/dock/weather-icons/rain-showers-moderate-day.png"
                    : "/io/elementary/dock/weather-icons/rain-showers-moderate-night.png";
            case 82:
                return "/io/elementary/dock/weather-icons/rain-heavy.png";
            case 85:
                return is_day
                    ? "/io/elementary/dock/weather-icons/snow-showers-light-day.png"
                    : "/io/elementary/dock/weather-icons/snow-showers-light-night.png";
            case 86:
                return "/io/elementary/dock/weather-icons/snow-showers-heavy.png";
            case 95:
                return "/io/elementary/dock/weather-icons/thunderstorms.png";
            case 96:
                return "/io/elementary/dock/weather-icons/thunderstorms-hail.png";
            case 99:
                return "/io/elementary/dock/weather-icons/thunderstorms-overcast.png";
            default:
                return "/io/elementary/dock/weather-icons/not-available.png";
        }
    }
}
