/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.GpuWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 2;

    private class DetailsPopover : Gtk.Popover {
        class construct {
            set_css_name ("tooltip");
        }
    }

    private Gtk.Label value_label;
    private Gtk.Box fill_overlay;
    private Gtk.Label details_usage_value_label;
    private Gtk.Label details_source_value_label;
    private Gtk.Label details_refresh_value_label;
    private uint refresh_timeout_id = 0;
    private string current_fill_class = "";
    private int current_usage_percent = 0;
    private bool has_usage_data = false;
    private string current_source_label = "Unavailable";

    public GpuWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("gpu-widlet-item");

        var title_label = new Gtk.Label ("GPU") {
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

        var icon = new Gtk.Image.from_resource ("/io/elementary/dock/widlet-icons/gpu-image.png") {
            pixel_size = 50,
            halign = END,
            valign = END,
            can_target = false
        };
        icon.add_css_class ("usage-widlet-icon");

        var content = new Gtk.Overlay () {
            child = new Gtk.Box (HORIZONTAL, 0),
            overflow = HIDDEN
        };
        content.add_css_class ("usage-widlet-content");
        content.add_overlay (fill_overlay);
        content.set_measure_overlay (fill_overlay, false);
        content.add_overlay (icon);
        content.set_measure_overlay (icon, false);
        content.add_overlay (text_box);
        content.set_measure_overlay (text_box, false);

        child = content;

        var details_title = new Gtk.Label (_("GPU Details")) {
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

        refresh_usage ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_usage ();
            return Source.CONTINUE;
        });
    }

    ~GpuWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }

        popover_menu.unparent ();
        popover_menu.dispose ();
    }

    private void refresh_usage () {
        int usage_percent = 0;
        string source_label = "Unavailable";
        var has_data = read_gpu_usage (out usage_percent, out source_label);
        current_source_label = source_label;
        update_usage (usage_percent, has_data);
    }

    private void update_usage (int usage_percent, bool has_data) {
        current_usage_percent = usage_percent;
        has_usage_data = has_data;

        if (has_data) {
            value_label.label = "%d%%".printf (usage_percent);
            tooltip_text = "GPU %d%%".printf (usage_percent);
            set_fill_class (get_fill_class_for_percentage (usage_percent));
        } else {
            value_label.label = "--";
            tooltip_text = _("GPU usage unavailable");
            set_fill_class ("usage-widlet-fill-unknown");
            current_source_label = "Unavailable";
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

        add_details_row (grid, 0, _("Usage"), out details_usage_value_label);
        add_details_row (grid, 1, _("Source"), out details_source_value_label);
        add_details_row (grid, 2, _("Refresh"), out details_refresh_value_label);
        details_refresh_value_label.label = _("2s");

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
        details_usage_value_label.label = has_usage_data ? "%d%%".printf (current_usage_percent) : "--";
        details_source_value_label.label = current_source_label;
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

    private static bool read_gpu_usage (out int usage_percent, out string source_label) {
        usage_percent = 0;
        source_label = "Unavailable";

        if (read_sysfs_gpu_usage (out usage_percent)) {
            source_label = "sysfs";
            return true;
        }

        if (read_nvidia_smi_usage (out usage_percent)) {
            source_label = "nvidia-smi";
            return true;
        }

        return false;
    }

    private static bool read_sysfs_gpu_usage (out int usage_percent) {
        usage_percent = 0;

        try {
            var drm_dir = Dir.open ("/sys/class/drm", 0);
            string? entry_name = null;
            while ((entry_name = drm_dir.read_name ()) != null) {
                if (!entry_name.has_prefix ("card") || entry_name.contains ("-")) {
                    continue;
                }

                if (read_percentage_file ("/sys/class/drm/%s/device/gpu_busy_percent".printf (entry_name), out usage_percent)) {
                    return true;
                }

                if (read_percentage_file ("/sys/class/drm/%s/gt_busy_percent".printf (entry_name), out usage_percent)) {
                    return true;
                }
            }
        } catch (Error e) {
            return false;
        }

        return false;
    }

    private static bool read_percentage_file (string path, out int usage_percent) {
        usage_percent = 0;

        string contents = "";
        try {
            if (!FileUtils.get_contents (path, out contents)) {
                return false;
            }
        } catch (Error e) {
            return false;
        }

        var value_text = contents.strip ();
        if (value_text == "" || !Regex.match_simple ("^[0-9]+$", value_text)) {
            return false;
        }

        int parsed_value = 0;
        if (!int.try_parse (value_text, out parsed_value)) {
            return false;
        }

        usage_percent = clamp_percentage (parsed_value);
        return true;
    }

    private static bool read_nvidia_smi_usage (out int usage_percent) {
        usage_percent = 0;

        string stdout = "";
        string stderr = "";
        int status = 1;

        try {
            Process.spawn_command_line_sync (
                "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits",
                out stdout,
                out stderr,
                out status
            );
        } catch (Error e) {
            return false;
        }

        if (status != 0 || stdout.strip () == "") {
            return false;
        }

        foreach (var raw_line in stdout.split ("\n")) {
            var line = raw_line.strip ();
            if (line == "" || !Regex.match_simple ("^[0-9]+$", line)) {
                continue;
            }

            int parsed_value = 0;
            if (int.try_parse (line, out parsed_value)) {
                usage_percent = clamp_percentage (parsed_value);
                return true;
            }
        }

        return false;
    }
}
