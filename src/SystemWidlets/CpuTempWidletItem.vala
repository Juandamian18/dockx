/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.CpuTempWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 2;

    private Gtk.Label value_label;
    private Gtk.Box fill_overlay;
    private uint refresh_timeout_id = 0;
    private string current_fill_class = "";

    public CpuTempWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("cputemp-widlet-item");

        var title_label = new Gtk.Label ("TEMP") {
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

        var icon = new Gtk.Image.from_resource ("/io/elementary/dock/widlet-icons/cputemp-image.png") {
            pixel_size = 48,
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

        refresh_temperature ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_temperature ();
            return Source.CONTINUE;
        });
    }

    ~CpuTempWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }
    }

    private void refresh_temperature () {
        int temperature_c = 0;
        var has_data = read_cpu_temperature (out temperature_c);
        update_temperature (temperature_c, has_data);
    }

    private void update_temperature (int temperature_c, bool has_data) {
        if (has_data) {
            value_label.label = "%d°".printf (temperature_c);
            tooltip_text = _("CPU temperature %d°C").printf (temperature_c);
            set_fill_class (get_fill_class_for_temperature (temperature_c));
        } else {
            value_label.label = "--";
            tooltip_text = _("CPU temperature unavailable");
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

    private static string get_fill_class_for_temperature (int temperature_c) {
        if (temperature_c >= 85) {
            return "usage-widlet-fill-high";
        }
        if (temperature_c >= 70) {
            return "usage-widlet-fill-medium";
        }

        return "usage-widlet-fill-low";
    }

    private static bool read_cpu_temperature (out int temperature_c) {
        temperature_c = 0;

        if (read_hwmon_temperature (out temperature_c)) {
            return true;
        }

        if (read_thermal_zone_temperature (out temperature_c)) {
            return true;
        }

        return false;
    }

    private static bool read_hwmon_temperature (out int temperature_c) {
        temperature_c = 0;
        var found_any = false;
        int best_fallback = 0;

        try {
            var hwmon_dir = Dir.open ("/sys/class/hwmon", 0);
            string? entry_name = null;
            while ((entry_name = hwmon_dir.read_name ()) != null) {
                if (!entry_name.has_prefix ("hwmon")) {
                    continue;
                }

                var base_path = "/sys/class/hwmon/%s".printf (entry_name);
                var chip_name = "";
                read_file_contents ("%s/name".printf (base_path), out chip_name);
                chip_name = chip_name.strip ().down ();
                var preferred_sensor = is_preferred_hwmon_sensor (chip_name);

                int sensor_temp = 0;
                if (!read_max_temp_input_from_dir (base_path, out sensor_temp)) {
                    continue;
                }

                sensor_temp = clamp_temperature (sensor_temp);
                if (preferred_sensor) {
                    temperature_c = sensor_temp;
                    return true;
                }

                if (!found_any || sensor_temp > best_fallback) {
                    best_fallback = sensor_temp;
                    found_any = true;
                }
            }
        } catch (Error e) {
            return false;
        }

        if (found_any) {
            temperature_c = best_fallback;
            return true;
        }

        return false;
    }

    private static bool read_thermal_zone_temperature (out int temperature_c) {
        temperature_c = 0;
        var found_any = false;
        int best_fallback = 0;

        try {
            var thermal_dir = Dir.open ("/sys/class/thermal", 0);
            string? entry_name = null;
            while ((entry_name = thermal_dir.read_name ()) != null) {
                if (!entry_name.has_prefix ("thermal_zone")) {
                    continue;
                }

                var base_path = "/sys/class/thermal/%s".printf (entry_name);
                var type_name = "";
                read_file_contents ("%s/type".printf (base_path), out type_name);
                type_name = type_name.strip ().down ();

                int milli_c = 0;
                if (!read_millidegree_value ("%s/temp".printf (base_path), out milli_c)) {
                    continue;
                }

                var temp_c = clamp_temperature ((int) Math.round ((double) milli_c / 1000.0));
                if (is_cpu_thermal_type (type_name)) {
                    temperature_c = temp_c;
                    return true;
                }

                if (!found_any || temp_c > best_fallback) {
                    best_fallback = temp_c;
                    found_any = true;
                }
            }
        } catch (Error e) {
            return false;
        }

        if (found_any) {
            temperature_c = best_fallback;
            return true;
        }

        return false;
    }

    private static bool read_max_temp_input_from_dir (string dir_path, out int temperature_c) {
        temperature_c = 0;
        var found_any = false;
        int max_temp = 0;

        try {
            var dir = Dir.open (dir_path, 0);
            string? entry_name = null;
            while ((entry_name = dir.read_name ()) != null) {
                if (!Regex.match_simple ("^temp[0-9]+_input$", entry_name)) {
                    continue;
                }

                int milli_c = 0;
                if (!read_millidegree_value ("%s/%s".printf (dir_path, entry_name), out milli_c)) {
                    continue;
                }

                var temp_c = (int) Math.round ((double) milli_c / 1000.0);
                if (!found_any || temp_c > max_temp) {
                    max_temp = temp_c;
                    found_any = true;
                }
            }
        } catch (Error e) {
            return false;
        }

        if (found_any) {
            temperature_c = max_temp;
            return true;
        }

        return false;
    }

    private static bool read_millidegree_value (string path, out int milli_c) {
        milli_c = 0;

        string raw_value = "";
        if (!read_file_contents (path, out raw_value)) {
            return false;
        }

        var value_text = raw_value.strip ();
        if (value_text == "" || !Regex.match_simple ("^-?[0-9]+$", value_text)) {
            return false;
        }

        int parsed = 0;
        if (!int.try_parse (value_text, out parsed)) {
            return false;
        }

        milli_c = parsed;
        return true;
    }

    private static bool read_file_contents (string path, out string contents) {
        contents = "";

        try {
            if (!FileUtils.get_contents (path, out contents)) {
                return false;
            }
        } catch (Error e) {
            return false;
        }

        return true;
    }

    private static bool is_preferred_hwmon_sensor (string chip_name) {
        if (chip_name.contains ("coretemp")) {
            return true;
        }
        if (chip_name.contains ("k10temp")) {
            return true;
        }
        if (chip_name.contains ("zenpower")) {
            return true;
        }
        if (chip_name.contains ("cpu")) {
            return true;
        }

        return false;
    }

    private static bool is_cpu_thermal_type (string type_name) {
        if (type_name.contains ("x86_pkg_temp")) {
            return true;
        }
        if (type_name.contains ("cpu")) {
            return true;
        }
        if (type_name.contains ("package")) {
            return true;
        }
        if (type_name.contains ("soc")) {
            return true;
        }

        return false;
    }

    private static int clamp_temperature (int temperature_c) {
        if (temperature_c < -40) {
            return -40;
        }
        if (temperature_c > 150) {
            return 150;
        }

        return temperature_c;
    }
}
