/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.HarddiskWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 1;
    private const int BASE_ICON_PIXEL_SIZE = 50;
    private const int BASE_FILL_HEIGHT = 22;

    private class DetailsPopover : Gtk.Popover {
        class construct {
            set_css_name ("tooltip");
        }
    }

    private Gtk.Label value_label;
    private Gtk.Box fill_overlay;
    private Gtk.Image icon_image;
    private Gtk.Label details_activity_value_label;
    private Gtk.Label details_devices_value_label;
    private Gtk.Label details_busy_time_value_label;
    private uint refresh_timeout_id = 0;
    private string current_fill_class = "";
    private bool has_previous_sample = false;
    private uint64 previous_io_millis = 0;
    private int64 previous_timestamp_ms = 0;
    private int current_usage_percent = 0;
    private bool has_activity_data = false;
    private uint current_tracked_devices = 0;
    private uint64 current_busy_millis_per_second = 0;

    public HarddiskWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("harddisk-widlet-item");

        var title_label = new Gtk.Label ("DISK") {
            xalign = 0
        };
        title_label.add_css_class ("usage-widlet-title");

        value_label = new Gtk.Label ("--") {
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

        icon_image = new Gtk.Image.from_resource ("/io/elementary/dock/widlet-icons/harddisk-image.png") {
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

        var details_title = new Gtk.Label (_("Disk Details")) {
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

        refresh_usage ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_usage ();
            return Source.CONTINUE;
        });
    }

    ~HarddiskWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }

        popover_menu.unparent ();
        popover_menu.dispose ();
    }

    private void refresh_usage () {
        int usage_percent = 0;
        uint64 current_io_millis = 0;
        uint tracked_devices = 0;
        var now_ms = GLib.get_monotonic_time () / 1000;

        if (!read_total_disk_io_millis (out current_io_millis, out tracked_devices)) {
            has_activity_data = false;
            current_tracked_devices = 0;
            current_busy_millis_per_second = 0;
            update_usage (0, false);
            return;
        }

        current_tracked_devices = tracked_devices;

        if (has_previous_sample && now_ms > previous_timestamp_ms && current_io_millis >= previous_io_millis) {
            var delta_io_millis = current_io_millis - previous_io_millis;
            var delta_elapsed_millis = (uint64) (now_ms - previous_timestamp_ms);

            if (delta_elapsed_millis > 0) {
                usage_percent = clamp_percentage ((int) Math.round ((double) delta_io_millis * 100.0 / (double) delta_elapsed_millis));
                current_busy_millis_per_second = (delta_io_millis * 1000) / delta_elapsed_millis;
            } else {
                current_busy_millis_per_second = 0;
            }
            update_usage (usage_percent, true);
        } else {
            current_busy_millis_per_second = 0;
            update_usage (0, true);
        }

        previous_io_millis = current_io_millis;
        previous_timestamp_ms = now_ms;
        has_previous_sample = true;
    }

    private void update_usage (int usage_percent, bool has_data) {
        current_usage_percent = usage_percent;
        has_activity_data = has_data;

        if (has_data) {
            value_label.label = "%d%%".printf (usage_percent);
            tooltip_text = _("Disk activity %d%%").printf (usage_percent);
            set_fill_class (get_fill_class_for_percentage (usage_percent));
        } else {
            value_label.label = "--";
            tooltip_text = _("Disk activity unavailable");
            set_fill_class ("usage-widlet-fill-unknown");
        }

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

        add_details_row (grid, 0, _("Activity"), out details_activity_value_label);
        add_details_row (grid, 1, _("Devices"), out details_devices_value_label);
        add_details_row (grid, 2, _("Busy Time"), out details_busy_time_value_label);

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
        details_devices_value_label.label = "%u".printf (current_tracked_devices);
        if (!has_activity_data) {
            details_activity_value_label.label = "--";
            details_busy_time_value_label.label = "--";
            return;
        }

        details_activity_value_label.label = "%d%%".printf (current_usage_percent);
        details_busy_time_value_label.label = "%.0f ms/s".printf ((double) current_busy_millis_per_second);
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
        icon_image.pixel_size = clamp_int ((int) Math.round (BASE_ICON_PIXEL_SIZE * scale), 30, 72);
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

    private static bool read_total_disk_io_millis (out uint64 total_io_millis, out uint tracked_device_count) {
        total_io_millis = 0;
        tracked_device_count = 0;

        string contents = "";
        try {
            if (!FileUtils.get_contents ("/proc/diskstats", out contents)) {
                return false;
            }
        } catch (Error e) {
            return false;
        }

        var found_device = false;

        foreach (var raw_line in contents.split ("\n")) {
            var line = raw_line.strip ();
            if (line == "") {
                continue;
            }

            string[] fields = {};
            foreach (var raw_part in line.split (" ")) {
                var part = raw_part.strip ();
                if (part != "") {
                    fields += part;
                }
            }

            if (fields.length < 13) {
                continue;
            }

            var device_name = fields[2];
            if (!is_tracked_disk_device (device_name)) {
                continue;
            }

            var io_time_text = fields[12];
            if (!Regex.match_simple ("^[0-9]+$", io_time_text)) {
                continue;
            }

            total_io_millis += uint64.parse (io_time_text);
            found_device = true;
            tracked_device_count++;
        }

        return found_device;
    }

    private static bool is_tracked_disk_device (string device_name) {
        if (device_name.has_prefix ("loop") || device_name.has_prefix ("ram") || device_name.has_prefix ("zram")) {
            return false;
        }

        if (Regex.match_simple ("^sd[a-z]+$", device_name)) {
            return true;
        }
        if (Regex.match_simple ("^vd[a-z]+$", device_name)) {
            return true;
        }
        if (Regex.match_simple ("^xvd[a-z]+$", device_name)) {
            return true;
        }
        if (Regex.match_simple ("^nvme[0-9]+n[0-9]+$", device_name)) {
            return true;
        }
        if (Regex.match_simple ("^mmcblk[0-9]+$", device_name)) {
            return true;
        }
        if (Regex.match_simple ("^dm-[0-9]+$", device_name)) {
            return true;
        }

        return false;
    }
}
