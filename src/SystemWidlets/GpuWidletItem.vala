/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.GpuWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 2;

    private Gtk.Label value_label;
    private Gtk.Box fill_overlay;
    private uint refresh_timeout_id = 0;
    private string current_fill_class = "";

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
    }

    private void refresh_usage () {
        int usage_percent = 0;
        var has_data = read_gpu_usage (out usage_percent);
        update_usage (usage_percent, has_data);
    }

    private void update_usage (int usage_percent, bool has_data) {
        if (has_data) {
            value_label.label = "%d%%".printf (usage_percent);
            tooltip_text = "GPU %d%%".printf (usage_percent);
            set_fill_class (get_fill_class_for_percentage (usage_percent));
        } else {
            value_label.label = "--";
            tooltip_text = _("GPU usage unavailable");
            set_fill_class ("usage-widlet-fill-unknown");
        }
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

    private static bool read_gpu_usage (out int usage_percent) {
        usage_percent = 0;

        if (read_sysfs_gpu_usage (out usage_percent)) {
            return true;
        }

        if (read_nvidia_smi_usage (out usage_percent)) {
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
