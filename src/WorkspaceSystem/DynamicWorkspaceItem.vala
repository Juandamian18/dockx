/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 */

public class Dock.DynamicWorkspaceIcon : ContainerItem, WorkspaceItem {
    private const string WORKSPACE_WIDLET_KEY = "widlet-workspace-enabled";
    private const string WEATHER_WIDLET_KEY = "widlet-weather-enabled";
    private const string WIDLET_ORDER_KEY = "widlet-order";

    private const string WEATHER_MINIMAL_MODE_KEY = "widlet-weather-minimal-mode";
    private const string WEATHER_LOCATION_KEY = "widlet-weather-location";
    private const string WEATHER_LATITUDE_KEY = "widlet-weather-latitude";
    private const string WEATHER_LONGITUDE_KEY = "widlet-weather-longitude";
    private const string WEATHER_UNIT_KEY = "widlet-weather-unit";
    private const string WEATHER_SIM_ENABLED_KEY = "widlet-weather-sim-enabled";
    private const string WEATHER_SIM_CODE_KEY = "widlet-weather-sim-weather-code";
    private const string WEATHER_SIM_TEMPERATURE_KEY = "widlet-weather-sim-temperature";
    private const string WEATHER_SIM_HOUR_KEY = "widlet-weather-sim-hour";

    private const string WIDLET_ID_WORKSPACE = "workspace";
    private const string WIDLET_ID_WEATHER = "weather";

    public int workspace_index { get { return WorkspaceSystem.get_default ().workspaces.length; } }

    private Gtk.Image image;
    private Gtk.Window? widlet_window = null;
    private Gtk.Window? weather_settings_window = null;
    private Gtk.Window? workspace_settings_window = null;
    private Gtk.Box? widlet_list_box = null;
    private string[] widlet_order = {};
    private static Soup.Session? geocoding_session = null;

    public DynamicWorkspaceIcon () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        image = new Gtk.Image.from_icon_name ("list-add-symbolic") {
            hexpand = true,
            vexpand = true
        };
        image.add_css_class ("add-image");

        child = image;
        tooltip_text = _("New Widlet");

        WorkspaceSystem.get_default ().workspace_added.connect (update_active_state);
        WorkspaceSystem.get_default ().workspace_removed.connect (update_active_state);
        WindowSystem.get_default ().notify["active-workspace"].connect (update_active_state);
        update_active_state ();

        dock_settings.bind_with_mapping (
            "icon-size", image, "pixel_size", DEFAULT | GET,
            (value, variant, user_data) => {
                var icon_size = variant.get_int32 ();
                value.set_int (icon_size / 2);
                return true;
            },
            (value, expected_type, user_data) => {
                return new Variant.maybe (null, null);
            },
            null, null
        );

        gesture_click.button = Gdk.BUTTON_PRIMARY;
        gesture_click.released.connect ((n_press, x, y) => {
            open_widlet_window ();
            popover_tooltip.popdown ();
        });
    }

    ~DynamicWorkspaceIcon () {
        if (widlet_window != null) {
            widlet_window.destroy ();
        }

        if (weather_settings_window != null) {
            weather_settings_window.destroy ();
        }

        if (workspace_settings_window != null) {
            workspace_settings_window.destroy ();
        }
    }

    private void update_active_state () {
        unowned var workspace_system = WorkspaceSystem.get_default ();
        unowned var window_system = WindowSystem.get_default ();
        state = (workspace_system.workspaces.length == window_system.active_workspace) ? State.ACTIVE : State.HIDDEN;
    }

    public void window_entered (Window window) {
        image.gicon = window.icon;
        set_state_flags (DROP_ACTIVE, false);
    }

    public void window_left () {
        image.icon_name = "list-add-symbolic";
        unset_state_flags (DROP_ACTIVE);
    }

    private void open_widlet_window () {
        if (widlet_window != null) {
            refresh_widlet_rows ();
            widlet_window.present ();
            return;
        }

        widlet_order = load_widlet_order ();

        var title = new Gtk.Label (_("New Widlet")) {
            xalign = 0
        };
        title.add_css_class ("title-3");

        var subtitle = new Gtk.Label (_("Browse your dock widlets, toggle visibility, reorder them, and open each widlet settings panel.")) {
            xalign = 0,
            wrap = true,
            max_width_chars = 44
        };
        subtitle.add_css_class (Granite.CssClass.DIM);
        subtitle.add_css_class ("widlet-store-subtitle");

        widlet_list_box = new Gtk.Box (VERTICAL, 8) {
            vexpand = true
        };
        widlet_list_box.add_css_class ("widlet-store-list");
        refresh_widlet_rows ();

        var content = new Gtk.Box (VERTICAL, 12) {
            margin_start = 16,
            margin_end = 16,
            margin_top = 16,
            margin_bottom = 16,
            width_request = 470
        };
        content.add_css_class ("widlet-store-window");
        content.append (title);
        content.append (subtitle);
        content.append (widlet_list_box);

        widlet_window = new Gtk.Window () {
            title = _("New Widlet"),
            child = content,
            resizable = false,
            modal = false,
            hide_on_close = true
        };

        attach_window_to_application (widlet_window);
        widlet_window.present ();
    }

    private void attach_window_to_application (Gtk.Window window) {
        var app = GLib.Application.get_default ();
        if (app is Gtk.Application) {
            var gtk_app = (Gtk.Application) app;
            gtk_app.add_window (window);

            if (widlet_window != null && window != widlet_window) {
                window.transient_for = widlet_window;
            } else if (gtk_app.active_window != null && gtk_app.active_window != window) {
                window.transient_for = gtk_app.active_window;
            }
        }
    }

    private void refresh_widlet_rows () {
        if (widlet_list_box == null) {
            return;
        }

        widlet_order = normalize_widlet_order (widlet_order);
        clear_box (widlet_list_box);

        foreach (var widlet_id in widlet_order) {
            switch (widlet_id) {
                case WIDLET_ID_WEATHER:
                    widlet_list_box.append (create_widlet_store_row (
                        widlet_id,
                        "weather-overcast-symbolic",
                        _("Weather Widlet"),
                        _("Current weather card with city, temperature, icon and forecast panel."),
                        true
                    ));
                    break;
                case WIDLET_ID_WORKSPACE:
                    widlet_list_box.append (create_widlet_store_row (
                        widlet_id,
                        "view-grid-symbolic",
                        _("Workspace Widlet"),
                        _("Workspace groups and app clusters on the right side of the dock."),
                        false
                    ));
                    break;
                default:
                    break;
            }
        }
    }

    private Gtk.Widget create_widlet_store_row (
        string widlet_id,
        string icon_name,
        string title,
        string description,
        bool has_settings
    ) {
        const int action_button_size = 28;
        var row_index = get_widlet_index (widlet_id);

        Gtk.Image icon;
        if (widlet_id == WIDLET_ID_WEATHER) {
            icon = new Gtk.Image.from_resource ("/io/elementary/dock/weather-icons/overcast.png") {
                pixel_size = 22,
                halign = CENTER,
                valign = CENTER
            };
        } else {
            icon = new Gtk.Image.from_icon_name (icon_name) {
                pixel_size = 22,
                halign = CENTER,
                valign = CENTER
            };
        }
        icon.add_css_class ("widlet-store-icon");

        var icon_wrap = new Gtk.Box (HORIZONTAL, 0) {
            halign = CENTER,
            valign = CENTER
        };
        icon_wrap.add_css_class ("widlet-store-icon-wrap");
        icon_wrap.append (icon);

        var row_title = new Gtk.Label (title) {
            xalign = 0,
            hexpand = true
        };
        row_title.add_css_class ("widlet-store-title");

        var row_description = new Gtk.Label (description) {
            xalign = 0,
            wrap = true,
            max_width_chars = 36
        };
        row_description.add_css_class (Granite.CssClass.DIM);
        row_description.add_css_class (Granite.CssClass.SMALL);
        row_description.add_css_class ("widlet-store-description");

        var row_text = new Gtk.Box (VERTICAL, 3) {
            hexpand = true,
            valign = CENTER
        };
        row_text.append (row_title);
        row_text.append (row_description);

        var row_switch = new Gtk.Switch () {
            halign = END,
            valign = CENTER
        };
        bind_widlet_switch (widlet_id, row_switch);

        var move_up_button = new Gtk.Button.from_icon_name ("go-up-symbolic") {
            tooltip_text = _("Move up"),
            valign = CENTER,
            width_request = action_button_size,
            height_request = action_button_size,
            sensitive = row_index > 0
        };
        move_up_button.add_css_class ("flat");
        move_up_button.clicked.connect (() => move_widlet (widlet_id, -1));

        var move_down_button = new Gtk.Button.from_icon_name ("go-down-symbolic") {
            tooltip_text = _("Move down"),
            valign = CENTER,
            width_request = action_button_size,
            height_request = action_button_size,
            sensitive = row_index >= 0 && row_index < widlet_order.length - 1
        };
        move_down_button.add_css_class ("flat");
        move_down_button.clicked.connect (() => move_widlet (widlet_id, +1));

        var reorder_controls = new Gtk.Box (VERTICAL, 2) {
            valign = CENTER,
            width_request = action_button_size
        };
        reorder_controls.append (move_up_button);
        reorder_controls.append (move_down_button);

        var settings_button = new Gtk.Button.from_icon_name ("emblem-system-symbolic") {
            valign = CENTER,
            width_request = action_button_size,
            height_request = action_button_size
        };
        settings_button.add_css_class ("flat");
        settings_button.add_css_class ("widlet-store-settings-button");
        if (has_settings) {
            settings_button.tooltip_text = _("Configure widlet");
            settings_button.clicked.connect (() => open_widlet_settings_window (widlet_id));
        } else {
            // Keep column width for alignment but hide the control when settings are unavailable.
            settings_button.sensitive = false;
            settings_button.opacity = 0;
            settings_button.can_target = false;
            settings_button.focusable = false;
        }

        var actions = new Gtk.Box (HORIZONTAL, 4) {
            halign = END,
            valign = CENTER
        };
        actions.add_css_class ("widlet-store-actions");
        actions.append (reorder_controls);
        actions.append (settings_button);
        actions.append (row_switch);

        var row_content = new Gtk.Box (HORIZONTAL, 12) {
            margin_start = 12,
            margin_end = 12,
            margin_top = 10,
            margin_bottom = 10,
            valign = CENTER
        };
        row_content.append (icon_wrap);
        row_content.append (row_text);
        row_content.append (actions);

        var row = new Gtk.Box (VERTICAL, 0);
        row.add_css_class ("widlet-store-row");
        row.append (row_content);
        return row;
    }

    private void bind_widlet_switch (string widlet_id, Gtk.Switch row_switch) {
        string key = widlet_id == WIDLET_ID_WEATHER ? WEATHER_WIDLET_KEY : WORKSPACE_WIDLET_KEY;

        if (dock_settings.settings_schema.has_key (key)) {
            dock_settings.bind (key, row_switch, "active", DEFAULT);
        } else {
            row_switch.active = true;
            row_switch.sensitive = false;
        }
    }

    private void open_widlet_settings_window (string widlet_id) {
        switch (widlet_id) {
            case WIDLET_ID_WEATHER:
                open_weather_settings_window ();
                break;
            case WIDLET_ID_WORKSPACE:
                open_workspace_settings_window ();
                break;
            default:
                break;
        }
    }

    private void open_workspace_settings_window () {
        if (workspace_settings_window != null) {
            workspace_settings_window.present ();
            return;
        }

        var title = new Gtk.Label (_("Workspace Widlet")) {
            xalign = 0
        };
        title.add_css_class ("title-3");

        var description = new Gtk.Label (_("No extra settings are available for this widlet yet.")) {
            xalign = 0,
            wrap = true,
            max_width_chars = 34
        };
        description.add_css_class (Granite.CssClass.DIM);

        var content = new Gtk.Box (VERTICAL, 8) {
            margin_start = 16,
            margin_end = 16,
            margin_top = 16,
            margin_bottom = 16,
            width_request = 340
        };
        content.add_css_class ("widlet-settings-window");
        content.append (title);
        content.append (description);

        workspace_settings_window = new Gtk.Window () {
            title = _("Workspace Widlet Settings"),
            child = content,
            resizable = false,
            modal = false,
            hide_on_close = true
        };

        attach_window_to_application (workspace_settings_window);
        workspace_settings_window.present ();
    }

    private void open_weather_settings_window () {
        if (weather_settings_window != null) {
            weather_settings_window.present ();
            return;
        }

        var weather_minimal_mode_switch = new Gtk.Switch () {
            halign = END,
            valign = CENTER
        };

        if (dock_settings.settings_schema.has_key (WEATHER_MINIMAL_MODE_KEY)) {
            dock_settings.bind (WEATHER_MINIMAL_MODE_KEY, weather_minimal_mode_switch, "active", DEFAULT);
        } else {
            weather_minimal_mode_switch.active = false;
            weather_minimal_mode_switch.sensitive = false;
        }

        var weather_unit_combo = new Gtk.ComboBoxText ();
        weather_unit_combo.append ("celsius", _("Celsius (°C)"));
        weather_unit_combo.append ("fahrenheit", _("Fahrenheit (°F)"));

        var simulator_enabled_switch = new Gtk.Switch () {
            halign = END,
            valign = CENTER
        };

        var simulator_code_combo = new Gtk.ComboBoxText ();
        foreach (var code in get_open_meteo_weather_codes ()) {
            simulator_code_combo.append (code.to_string (), "%d - %s".printf (code, weather_code_to_preview_label (code)));
        }

        var simulator_temperature_spin = new Gtk.SpinButton.with_range (-50, 140, 1) {
            digits = 0,
            numeric = true,
            width_chars = 4
        };

        var simulator_hour_spin = new Gtk.SpinButton.with_range (0, 23, 1) {
            digits = 0,
            numeric = true,
            width_chars = 3
        };

        var simulator_temperature_unit_label = new Gtk.Label ("°C") {
            valign = CENTER
        };

        var simulator_temperature_control = new Gtk.Box (HORIZONTAL, 6) {
            halign = END
        };
        simulator_temperature_control.append (simulator_temperature_spin);
        simulator_temperature_control.append (simulator_temperature_unit_label);

        if (dock_settings.settings_schema.has_key (WEATHER_UNIT_KEY)) {
            var configured_unit = dock_settings.get_string (WEATHER_UNIT_KEY).strip ().down ();
            weather_unit_combo.active_id = configured_unit == "fahrenheit" ? "fahrenheit" : "celsius";

            weather_unit_combo.changed.connect (() => {
                var selected_unit = weather_unit_combo.get_active_id ();
                if (selected_unit == null || selected_unit == "") {
                    selected_unit = "celsius";
                }

                dock_settings.set_string (WEATHER_UNIT_KEY, selected_unit);
                simulator_temperature_unit_label.label = selected_unit == "fahrenheit" ? "°F" : "°C";
            });
        } else {
            weather_unit_combo.active_id = "celsius";
            weather_unit_combo.sensitive = false;
        }
        simulator_temperature_unit_label.label = weather_unit_combo.get_active_id () == "fahrenheit" ? "°F" : "°C";

        if (dock_settings.settings_schema.has_key (WEATHER_SIM_ENABLED_KEY)) {
            dock_settings.bind (WEATHER_SIM_ENABLED_KEY, simulator_enabled_switch, "active", DEFAULT);
        } else {
            simulator_enabled_switch.active = false;
            simulator_enabled_switch.sensitive = false;
        }

        if (dock_settings.settings_schema.has_key (WEATHER_SIM_CODE_KEY)) {
            simulator_code_combo.active_id = dock_settings.get_int (WEATHER_SIM_CODE_KEY).to_string ();
            if (simulator_code_combo.get_active_id () == null) {
                simulator_code_combo.active = 0;
            }

            simulator_code_combo.changed.connect (() => {
                var selected_code = simulator_code_combo.get_active_id ();
                if (selected_code == null || selected_code == "") {
                    return;
                }

                dock_settings.set_int (WEATHER_SIM_CODE_KEY, int.parse (selected_code));
            });
        } else {
            simulator_code_combo.active = 0;
            simulator_code_combo.sensitive = false;
        }

        if (dock_settings.settings_schema.has_key (WEATHER_SIM_TEMPERATURE_KEY)) {
            simulator_temperature_spin.value = dock_settings.get_double (WEATHER_SIM_TEMPERATURE_KEY);
            simulator_temperature_spin.value_changed.connect (() => {
                dock_settings.set_double (WEATHER_SIM_TEMPERATURE_KEY, simulator_temperature_spin.value);
            });
        } else {
            simulator_temperature_spin.sensitive = false;
        }

        if (dock_settings.settings_schema.has_key (WEATHER_SIM_HOUR_KEY)) {
            simulator_hour_spin.value = dock_settings.get_int (WEATHER_SIM_HOUR_KEY);
            simulator_hour_spin.value_changed.connect (() => {
                dock_settings.set_int (WEATHER_SIM_HOUR_KEY, (int) Math.round (simulator_hour_spin.value));
            });
        } else {
            simulator_hour_spin.sensitive = false;
        }

        var title = new Gtk.Label (_("Weather Widlet Settings")) {
            xalign = 0
        };
        title.add_css_class ("title-3");

        var subtitle = new Gtk.Label (_("Customize weather units, location, minimal mode and preview controls.")) {
            xalign = 0,
            wrap = true,
            max_width_chars = 42
        };
        subtitle.add_css_class (Granite.CssClass.DIM);
        subtitle.add_css_class ("widlet-settings-subtitle");

        var weather_section_title = new Gtk.Label (_("Appearance")) {
            xalign = 0
        };
        weather_section_title.add_css_class ("widlet-settings-section-title");

        var weather_location_title = new Gtk.Label (_("Weather Location")) {
            xalign = 0
        };
        weather_location_title.add_css_class ("widlet-settings-section-title");

        var city_entry = new Gtk.Entry () {
            hexpand = true,
            placeholder_text = _("Type your city")
        };
        if (dock_settings.settings_schema.has_key (WEATHER_LOCATION_KEY)) {
            city_entry.text = dock_settings.get_string (WEATHER_LOCATION_KEY);
        }

        var city_apply_button = new Gtk.Button.with_label (_("Use City")) {
            halign = END
        };
        city_apply_button.add_css_class (Granite.CssClass.SUGGESTED);

        var city_row = new Gtk.Box (HORIZONTAL, 8);
        city_row.append (city_entry);
        city_row.append (city_apply_button);

        var city_status = new Gtk.Label (_("Set your city and the widlet will update coordinates.")) {
            xalign = 0,
            wrap = true,
            max_width_chars = 40
        };
        city_status.add_css_class (Granite.CssClass.DIM);
        city_status.add_css_class (Granite.CssClass.SMALL);

        var location_box = new Gtk.Box (VERTICAL, 6);
        location_box.append (weather_location_title);
        location_box.append (city_row);
        location_box.append (city_status);

        var simulator_title = new Gtk.Label (_("Weather Preview Tool")) {
            xalign = 0
        };
        simulator_title.add_css_class ("widlet-settings-section-title");

        var simulator_subtitle = new Gtk.Label (_("Temporary tool to preview all Open-Meteo weather types.")) {
            xalign = 0,
            wrap = true,
            max_width_chars = 40
        };
        simulator_subtitle.add_css_class (Granite.CssClass.DIM);
        simulator_subtitle.add_css_class (Granite.CssClass.SMALL);

        var simulator_box = new Gtk.Box (VERTICAL, 8);
        simulator_box.append (simulator_title);
        simulator_box.append (simulator_subtitle);
        simulator_box.append (create_setting_row (
            _("Enable Preview"),
            _("Show simulated weather values instead of live Open-Meteo data."),
            simulator_enabled_switch
        ));
        simulator_box.append (new Gtk.Separator (HORIZONTAL));
        simulator_box.append (create_setting_row (
            _("Weather Type"),
            _("Select any weather code available in Open-Meteo."),
            simulator_code_combo
        ));
        simulator_box.append (new Gtk.Separator (HORIZONTAL));
        simulator_box.append (create_setting_row (
            _("Simulated Temperature"),
            _("Temperature shown in preview mode."),
            simulator_temperature_control
        ));
        simulator_box.append (new Gtk.Separator (HORIZONTAL));
        simulator_box.append (create_setting_row (
            _("Simulated Hour"),
            _("Hour 0-23 used for day/night gradient behavior."),
            simulator_hour_spin
        ));

        city_apply_button.clicked.connect (() => {
            geocode_and_store_city.begin (city_entry.text, city_status, city_entry);
        });
        city_entry.activate.connect (() => {
            geocode_and_store_city.begin (city_entry.text, city_status, city_entry);
        });

        var content = new Gtk.Box (VERTICAL, 10) {
            margin_start = 16,
            margin_end = 16,
            margin_top = 16,
            margin_bottom = 16,
            width_request = 430
        };
        content.add_css_class ("widlet-settings-window");
        content.append (title);
        content.append (subtitle);
        content.append (new Gtk.Separator (HORIZONTAL));
        content.append (weather_section_title);
        content.append (create_setting_row (
            _("Weather Minimal Mode"),
            _("Shows only temperature in dock width and reveals details on hover."),
            weather_minimal_mode_switch
        ));
        content.append (new Gtk.Separator (HORIZONTAL));
        content.append (create_setting_row (
            _("Temperature Unit"),
            _("Choose whether the weather widlet displays Celsius or Fahrenheit."),
            weather_unit_combo
        ));
        content.append (new Gtk.Separator (HORIZONTAL));
        content.append (location_box);
        content.append (new Gtk.Separator (HORIZONTAL));
        content.append (simulator_box);

        weather_settings_window = new Gtk.Window () {
            title = _("Weather Widlet Settings"),
            child = content,
            resizable = false,
            modal = false,
            hide_on_close = true
        };

        attach_window_to_application (weather_settings_window);
        weather_settings_window.present ();
    }

    private string[] load_widlet_order () {
        if (dock_settings.settings_schema.has_key (WIDLET_ORDER_KEY)) {
            return normalize_widlet_order (dock_settings.get_strv (WIDLET_ORDER_KEY));
        }

        return normalize_widlet_order ({});
    }

    private string[] normalize_widlet_order (string[] raw_order) {
        string[] normalized = {};
        bool has_weather = false;
        bool has_workspace = false;

        foreach (var raw_id in raw_order) {
            var widlet_id = raw_id.strip ().down ();
            if (widlet_id == WIDLET_ID_WEATHER && !has_weather) {
                normalized += WIDLET_ID_WEATHER;
                has_weather = true;
            } else if (widlet_id == WIDLET_ID_WORKSPACE && !has_workspace) {
                normalized += WIDLET_ID_WORKSPACE;
                has_workspace = true;
            }
        }

        if (!has_weather) {
            normalized += WIDLET_ID_WEATHER;
        }
        if (!has_workspace) {
            normalized += WIDLET_ID_WORKSPACE;
        }

        return normalized;
    }

    private void persist_widlet_order () {
        widlet_order = normalize_widlet_order (widlet_order);

        if (dock_settings.settings_schema.has_key (WIDLET_ORDER_KEY)) {
            dock_settings.set_strv (WIDLET_ORDER_KEY, widlet_order);
        }
    }

    private int get_widlet_index (string widlet_id) {
        for (int i = 0; i < widlet_order.length; i++) {
            if (widlet_order[i] == widlet_id) {
                return i;
            }
        }

        return -1;
    }

    private void move_widlet (string widlet_id, int direction) {
        var current_index = get_widlet_index (widlet_id);
        if (current_index < 0) {
            return;
        }

        var new_index = current_index + direction;
        if (new_index < 0 || new_index >= widlet_order.length) {
            return;
        }

        var swapped = widlet_order[new_index];
        widlet_order[new_index] = widlet_order[current_index];
        widlet_order[current_index] = swapped;

        persist_widlet_order ();
        refresh_widlet_rows ();
    }

    private Gtk.Widget create_setting_row (string title, string description, Gtk.Widget control) {
        var row_title = new Gtk.Label (title) {
            xalign = 0,
            hexpand = true
        };

        var row_description = new Gtk.Label (description) {
            xalign = 0,
            wrap = true,
            max_width_chars = 30
        };
        row_description.add_css_class (Granite.CssClass.DIM);
        row_description.add_css_class (Granite.CssClass.SMALL);

        var row_text = new Gtk.Box (VERTICAL, 2) {
            hexpand = true,
            valign = CENTER
        };
        row_text.append (row_title);
        row_text.append (row_description);

        var row = new Gtk.Box (HORIZONTAL, 12);
        row.add_css_class ("widlet-settings-row");
        row.append (row_text);
        row.append (control);
        return row;
    }

    private static void clear_box (Gtk.Box box) {
        var child = box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            box.remove (child);
            child = next;
        }
    }

    private static int[] get_open_meteo_weather_codes () {
        return {
            0, 1, 2, 3,
            45, 48,
            51, 53, 55, 56, 57,
            61, 63, 65, 66, 67,
            71, 73, 75, 77, 80, 81, 82, 85, 86,
            95, 96, 99
        };
    }

    private static string weather_code_to_preview_label (int weather_code) {
        switch (weather_code) {
            case 0:
                return _("Clear sky");
            case 1:
                return _("Mainly clear");
            case 2:
                return _("Partly cloudy");
            case 3:
                return _("Mostly cloudy");
            case 45:
            case 48:
                return _("Fog");
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
            case 80:
                return _("Slight rain showers");
            case 81:
                return _("Moderate rain showers");
            case 82:
                return _("Violent rain showers");
            case 85:
                return _("Slight snow showers");
            case 86:
                return _("Heavy snow showers");
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

    private async void geocode_and_store_city (string raw_query, Gtk.Label status_label, Gtk.Entry city_entry) {
        var query = raw_query.strip ();
        if (query == "") {
            status_label.label = _("Enter a city name.");
            return;
        }

        if (geocoding_session == null) {
            geocoding_session = new Soup.Session () {
                timeout = 10
            };
        }

        status_label.label = _("Searching city...");

        try {
            var encoded_query = Uri.escape_string (query, null, false);
            var url = "https://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=en&format=json".printf (encoded_query);

            var message = new Soup.Message ("GET", url);
            var bytes = yield geocoding_session.send_and_read_async (message, Priority.DEFAULT, null);

            if (message.status_code != Soup.Status.OK) {
                throw new IOError.FAILED ("Unexpected geocoding response HTTP %u".printf (message.status_code));
            }

            var payload = (string) bytes.get_data ();
            if (is_empty_results (payload)) {
                status_label.label = _("City not found.");
                return;
            }

            double latitude = 0;
            double longitude = 0;
            string city_name = "";
            string admin_name = "";
            string country_name = "";

            if (!parse_double_field (payload, "latitude", out latitude) ||
                !parse_double_field (payload, "longitude", out longitude) ||
                !parse_string_field (payload, "name", out city_name)) {
                status_label.label = _("Could not parse city response.");
                return;
            }

            parse_string_field (payload, "admin1", out admin_name);
            parse_string_field (payload, "country", out country_name);

            var location_label = city_name;
            if (admin_name != "" && country_name != "") {
                location_label = "%s, %s, %s".printf (city_name, admin_name, country_name);
            } else if (admin_name != "") {
                location_label = "%s, %s".printf (city_name, admin_name);
            } else if (country_name != "") {
                location_label = "%s, %s".printf (city_name, country_name);
            }

            if (dock_settings.settings_schema.has_key (WEATHER_LOCATION_KEY)) {
                dock_settings.set_string (WEATHER_LOCATION_KEY, location_label);
            }
            if (dock_settings.settings_schema.has_key (WEATHER_LATITUDE_KEY)) {
                dock_settings.set_double (WEATHER_LATITUDE_KEY, latitude);
            }
            if (dock_settings.settings_schema.has_key (WEATHER_LONGITUDE_KEY)) {
                dock_settings.set_double (WEATHER_LONGITUDE_KEY, longitude);
            }

            city_entry.text = location_label;
            status_label.label = _("Location updated.");
        } catch (Error e) {
            warning ("City geocoding failed: %s", e.message);
            status_label.label = _("Could not find city.");
        }
    }

    private static bool is_empty_results (string payload) {
        try {
            var regex = new Regex ("\"results\"\\s*:\\s*\\[\\s*\\]");
            MatchInfo info;
            return regex.match (payload, 0, out info);
        } catch (Error e) {
            warning ("Could not parse results array: %s", e.message);
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
