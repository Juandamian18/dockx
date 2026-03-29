/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.RamWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 2;
    private const int BASE_ICON_PIXEL_SIZE = 46;
    private const int BASE_FILL_HEIGHT = 22;
    private const string ALERT_ENABLED_KEY = "widlet-ram-alert-enabled";
    private const string ALERT_THRESHOLD_KEY = "widlet-ram-alert-threshold";
    private const int ALERT_DEFAULT_THRESHOLD = 90;

    private class DetailsPopover : Gtk.Popover {
        class construct {
            set_css_name ("tooltip");
        }
    }

    private Gtk.Label value_label;
    private Gtk.Box fill_overlay;
    private Gtk.Image icon_image;
    private Gtk.Label details_usage_value_label;
    private Gtk.Label details_used_value_label;
    private Gtk.Label details_available_value_label;
    private Gtk.Label details_total_value_label;
    private uint refresh_timeout_id = 0;
    private string current_fill_class = "";
    private int current_usage_percent = 0;
    private uint64 current_total_kib = 0;
    private uint64 current_available_kib = 0;
    private bool has_memory_sample = false;
    private WidletAlertController alert_controller;

    public RamWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("ram-widlet-item");
        alert_controller = new WidletAlertController (
            this,
            ALERT_ENABLED_KEY,
            ALERT_THRESHOLD_KEY,
            "ram",
            _("RAM Widlet"),
            _("RAM usage"),
            "%"
        );

        var title_label = new Gtk.Label ("RAM") {
            xalign = 0
        };
        title_label.add_css_class ("usage-widlet-title");

        value_label = new Gtk.Label ("0%") {
            xalign = 0.5f
        };
        value_label.add_css_class ("usage-widlet-value");

        var top_spacer = new Gtk.Box (VERTICAL, 0) {
            vexpand = true
        };
        var bottom_spacer = new Gtk.Box (VERTICAL, 0) {
            vexpand = true
        };

        var text_box = new Gtk.Box (VERTICAL, 0) {
            halign = FILL,
            valign = FILL,
            margin_start = 4,
            margin_end = 4,
            margin_top = 3,
            margin_bottom = 3,
            can_target = false
        };
        text_box.append (title_label);
        text_box.append (top_spacer);
        text_box.append (value_label);
        text_box.append (bottom_spacer);

        fill_overlay = new Gtk.Box (HORIZONTAL, 0) {
            halign = FILL,
            valign = END,
            height_request = 22,
            margin_start = -4,
            margin_end = -4,
            can_target = false
        };
        fill_overlay.add_css_class ("usage-widlet-fill");

        icon_image = new Gtk.Image.from_resource ("/io/elementary/dock/widlet-icons/ram-image.png") {
            pixel_size = BASE_ICON_PIXEL_SIZE,
            halign = END,
            valign = END,
            can_target = false
        };
        icon_image.add_css_class ("usage-widlet-icon");

        var content = new Gtk.Overlay () {
            child = new Gtk.Box (HORIZONTAL, 0),
            overflow = HIDDEN
        };
        content.add_css_class ("usage-widlet-content");
        content.add_overlay (fill_overlay);
        content.set_measure_overlay (fill_overlay, false);
        content.add_overlay (icon_image);
        content.set_measure_overlay (icon_image, false);
        content.add_overlay (text_box);
        content.set_measure_overlay (text_box, false);

        child = content;

        var details_title = new Gtk.Label (_("RAM Details")) {
            xalign = 0
        };
        details_title.add_css_class ("widlet-details-title");

        var details_grid = create_details_grid ();

        var details_content = new Gtk.Box (VERTICAL, 8) {
            margin_start = 10,
            margin_end = 10,
            margin_top = 8,
            margin_bottom = 8,
            width_request = 250
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
        notify["icon-size"].connect (update_size_variant);
        update_size_variant ();

        update_usage (0);
        refresh_usage ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_usage ();
            return Source.CONTINUE;
        });
    }

    ~RamWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }

        popover_menu.unparent ();
        popover_menu.dispose ();
    }

    private void refresh_usage () {
        uint64 total_kib = 0;
        uint64 available_kib = 0;
        if (!read_memory_sample (out total_kib, out available_kib) || total_kib == 0) {
            has_memory_sample = false;
            alert_controller.evaluate_int (0, false, ALERT_DEFAULT_THRESHOLD);
            return;
        }

        if (available_kib > total_kib) {
            available_kib = total_kib;
        }

        current_total_kib = total_kib;
        current_available_kib = available_kib;
        has_memory_sample = true;

        var used_ratio = (double) (total_kib - available_kib) / (double) total_kib;
        var usage_percent = clamp_percentage ((int) Math.round (used_ratio * 100.0));
        update_usage (usage_percent);
    }

    private void update_usage (int usage_percent) {
        current_usage_percent = usage_percent;
        value_label.label = "%d%%".printf (usage_percent);
        tooltip_text = "RAM %d%%".printf (usage_percent);
        set_fill_class (get_fill_class_for_percentage (usage_percent));
        alert_controller.evaluate_int (usage_percent, true, ALERT_DEFAULT_THRESHOLD);
        refresh_details_labels ();
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

    private Gtk.Grid create_details_grid () {
        var grid = new Gtk.Grid () {
            column_spacing = 14,
            row_spacing = 6
        };
        grid.add_css_class ("widlet-details-grid");

        add_details_row (grid, 0, _("Usage"), out details_usage_value_label);
        add_details_row (grid, 1, _("Used"), out details_used_value_label);
        add_details_row (grid, 2, _("Available"), out details_available_value_label);
        add_details_row (grid, 3, _("Total"), out details_total_value_label);

        return grid;
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

    private void refresh_details_labels () {
        details_usage_value_label.label = "%d%%".printf (current_usage_percent);

        if (!has_memory_sample || current_total_kib == 0) {
            details_used_value_label.label = "--";
            details_available_value_label.label = "--";
            details_total_value_label.label = "--";
            return;
        }

        var used_kib = current_total_kib >= current_available_kib ? current_total_kib - current_available_kib : 0;
        details_used_value_label.label = format_kib_to_gib (used_kib);
        details_available_value_label.label = format_kib_to_gib (current_available_kib);
        details_total_value_label.label = format_kib_to_gib (current_total_kib);
    }

    private static string format_kib_to_gib (uint64 kib) {
        var gib = (double) kib / (1024.0 * 1024.0);
        return "%.1f GiB".printf (gib);
    }

    private void update_size_variant () {
        remove_css_class ("widlet-size-small");
        remove_css_class ("widlet-size-large");

        if (icon_size <= 40) {
            add_css_class ("widlet-size-small");
        } else if (icon_size >= 56) {
            add_css_class ("widlet-size-large");
        }

        var scale = (double) icon_size / 48.0;
        icon_image.pixel_size = clamp_int ((int) Math.round (BASE_ICON_PIXEL_SIZE * scale), 28, 68);
        fill_overlay.height_request = clamp_int ((int) Math.round (BASE_FILL_HEIGHT * scale), 16, 30);
    }

    private static int clamp_int (int value, int min, int max) {
        if (value < min) {
            return min;
        }
        if (value > max) {
            return max;
        }

        return value;
    }

    private void set_fill_class (string css_class) {
        if (current_fill_class != "") {
            fill_overlay.remove_css_class (current_fill_class);
        }

        fill_overlay.add_css_class (css_class);
        current_fill_class = css_class;
    }

    private static string get_fill_class_for_percentage (int usage_percent) {
        if (usage_percent >= 80) {
            return "usage-widlet-fill-high";
        }
        if (usage_percent >= 50) {
            return "usage-widlet-fill-medium";
        }

        return "usage-widlet-fill-low";
    }

    private static int clamp_percentage (int value) {
        if (value < 0) {
            return 0;
        }
        if (value > 100) {
            return 100;
        }

        return value;
    }

    private static bool read_memory_sample (out uint64 total_kib, out uint64 available_kib) {
        total_kib = 0;
        available_kib = 0;

        string contents = "";
        try {
            if (!FileUtils.get_contents ("/proc/meminfo", out contents)) {
                return false;
            }
        } catch (Error e) {
            return false;
        }

        foreach (var raw_line in contents.split ("\n")) {
            var line = raw_line.strip ();
            if (line.has_prefix ("MemTotal:")) {
                parse_meminfo_line (line, out total_kib);
            } else if (line.has_prefix ("MemAvailable:")) {
                parse_meminfo_line (line, out available_kib);
            }

            if (total_kib > 0 && available_kib > 0) {
                return true;
            }
        }

        return total_kib > 0 && available_kib > 0;
    }

    private static bool parse_meminfo_line (string line, out uint64 value_kib) {
        value_kib = 0;

        var parts = line.split (":");
        if (parts.length < 2) {
            return false;
        }

        foreach (var raw_token in parts[1].strip ().split (" ")) {
            var token = raw_token.strip ();
            if (token == "") {
                continue;
            }

            if (!Regex.match_simple ("^[0-9]+$", token)) {
                continue;
            }

            value_kib = uint64.parse (token);
            return true;
        }

        return false;
    }
}
