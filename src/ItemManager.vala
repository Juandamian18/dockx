/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2023-2025 elementary, Inc. (https://elementary.io)
 */

 public class Dock.ItemManager : Gtk.Fixed {
    private static Settings settings;

    private static GLib.Once<ItemManager> instance;
    public static unowned ItemManager get_default () {
        return instance.once (() => { return new ItemManager (); });
    }

    public Launcher? added_launcher { get; set; default = null; }

    private Adw.TimedAnimation resize_animation;
    private GLib.GenericArray<Launcher> launchers; // Only used to keep track of launcher indices
    private BackgroundItem background_item;
    private NowPlayingItem now_playing_item;
    private GLib.GenericArray<WorkspaceIconGroup> icon_groups; // Only used to keep track of icon group indices
    private DynamicWorkspaceIcon dynamic_workspace_item;

#if WORKSPACE_SWITCHER
    private const string WORKSPACE_WIDLET_KEY = "widlet-workspace-enabled";
    private const string WEATHER_WIDLET_KEY = "widlet-weather-enabled";
    private const string CPU_WIDLET_KEY = "widlet-cpu-enabled";
    private const string RAM_WIDLET_KEY = "widlet-ram-enabled";
    private const string CPUTEMP_WIDLET_KEY = "widlet-cputemp-enabled";
    private const string GPU_WIDLET_KEY = "widlet-gpu-enabled";
    private const string HARDDISK_WIDLET_KEY = "widlet-harddisk-enabled";
    private const string WIDLET_ORDER_KEY = "widlet-order";
    private const string WIDLET_ID_WEATHER = "weather";
    private const string WIDLET_ID_CPU = "cpu";
    private const string WIDLET_ID_RAM = "ram";
    private const string WIDLET_ID_CPUTEMP = "cputemp";
    private const string WIDLET_ID_GPU = "gpu";
    private const string WIDLET_ID_HARDDISK = "harddisk";
    private const string WIDLET_ID_WORKSPACE = "workspace";

    private Gtk.Separator separator;
    private bool workspace_widlet_enabled = true;
    private bool weather_widlet_enabled = true;
    private bool cpu_widlet_enabled = true;
    private bool ram_widlet_enabled = true;
    private bool cputemp_widlet_enabled = true;
    private bool gpu_widlet_enabled = true;
    private bool harddisk_widlet_enabled = true;
    private WeatherWidletItem weather_widlet_item;
    private CpuWidletItem cpu_widlet_item;
    private RamWidletItem ram_widlet_item;
    private CpuTempWidletItem cputemp_widlet_item;
    private GpuWidletItem gpu_widlet_item;
    private HarddiskWidletItem harddisk_widlet_item;
#endif

    static construct {
        settings = new Settings ("io.elementary.dock");
    }

    construct {
        launchers = new GLib.GenericArray<Launcher> ();

        background_item = new BackgroundItem ();
        background_item.apps_appeared.connect (add_item);

        now_playing_item = new NowPlayingItem ();
        now_playing_item.playback_appeared.connect (add_item);
        now_playing_item.mode_changed.connect (() => {
            reposition_items ();
            queue_resize ();
        });

        icon_groups = new GLib.GenericArray<WorkspaceIconGroup> ();

#if WORKSPACE_SWITCHER
        dynamic_workspace_item = new DynamicWorkspaceIcon ();
        weather_widlet_item = new WeatherWidletItem ();
        cpu_widlet_item = new CpuWidletItem ();
        ram_widlet_item = new RamWidletItem ();
        cputemp_widlet_item = new CpuTempWidletItem ();
        gpu_widlet_item = new GpuWidletItem ();
        harddisk_widlet_item = new HarddiskWidletItem ();
        weather_widlet_item.mode_changed.connect (() => {
            reposition_items ();
            queue_resize ();
        });

        separator = new Gtk.Separator (VERTICAL);
        settings.bind ("icon-size", separator, "height-request", GET);
        put (separator, 0, 0);
#endif

        overflow = VISIBLE;

        resize_animation = new Adw.TimedAnimation (
            this, 0, 0, 0,
            new Adw.CallbackAnimationTarget ((val) => {
                width_request = (int) val;
            })
        );

        resize_animation.done.connect (() => width_request = -1); //Reset otherwise we stay to big when the launcher icon size changes

        settings.changed["icon-size"].connect (reposition_items);

#if WORKSPACE_SWITCHER
        if (settings.settings_schema.has_key (WORKSPACE_WIDLET_KEY)) {
            workspace_widlet_enabled = settings.get_boolean (WORKSPACE_WIDLET_KEY);
            settings.changed[WORKSPACE_WIDLET_KEY].connect (update_workspace_widlet_state);
        }
        if (settings.settings_schema.has_key (WEATHER_WIDLET_KEY)) {
            weather_widlet_enabled = settings.get_boolean (WEATHER_WIDLET_KEY);
            settings.changed[WEATHER_WIDLET_KEY].connect (update_weather_widlet_state);
        }
        if (settings.settings_schema.has_key (CPU_WIDLET_KEY)) {
            cpu_widlet_enabled = settings.get_boolean (CPU_WIDLET_KEY);
            settings.changed[CPU_WIDLET_KEY].connect (update_cpu_widlet_state);
        }
        if (settings.settings_schema.has_key (RAM_WIDLET_KEY)) {
            ram_widlet_enabled = settings.get_boolean (RAM_WIDLET_KEY);
            settings.changed[RAM_WIDLET_KEY].connect (update_ram_widlet_state);
        }
        if (settings.settings_schema.has_key (CPUTEMP_WIDLET_KEY)) {
            cputemp_widlet_enabled = settings.get_boolean (CPUTEMP_WIDLET_KEY);
            settings.changed[CPUTEMP_WIDLET_KEY].connect (update_cputemp_widlet_state);
        }
        if (settings.settings_schema.has_key (GPU_WIDLET_KEY)) {
            gpu_widlet_enabled = settings.get_boolean (GPU_WIDLET_KEY);
            settings.changed[GPU_WIDLET_KEY].connect (update_gpu_widlet_state);
        }
        if (settings.settings_schema.has_key (HARDDISK_WIDLET_KEY)) {
            harddisk_widlet_enabled = settings.get_boolean (HARDDISK_WIDLET_KEY);
            settings.changed[HARDDISK_WIDLET_KEY].connect (update_harddisk_widlet_state);
        }
        if (settings.settings_schema.has_key (WIDLET_ORDER_KEY)) {
            settings.changed[WIDLET_ORDER_KEY].connect (() => {
                reposition_items ();
                queue_resize ();
            });
        }
#endif

        var drop_target_file = new Gtk.DropTarget (typeof (File), COPY) {
            preload = true
        };
        add_controller (drop_target_file);

        double drop_x, drop_y;
        drop_target_file.enter.connect ((x, y) => {
            drop_x = x;
            drop_y = y;
            return COPY;
        });

        drop_target_file.notify["value"].connect (() => {
            if (drop_target_file.get_value () == null) {
                return;
            }

            if (drop_target_file.get_value ().get_object () == null) {
                return;
            }

            if (!(drop_target_file.get_value ().get_object () is File)) {
                return;
            }

            var file = (File) drop_target_file.get_value ().get_object ();
            var app_info = new DesktopAppInfo.from_filename (file.get_path ());

            if (app_info == null) {
                return;
            }

            var app_system = AppSystem.get_default ();

            var app = app_system.get_app (app_info.get_id ());
            if (app != null) {
                app.pinned = true;
                drop_target_file.reject ();
                return;
            }

            app_system.add_app_for_id (app_info.get_id ());
        });

        BaseItem? current_base_item = null;
        drop_target_file.motion.connect ((x, y) => {
            if (added_launcher == null) {
                current_base_item = null;
                return COPY;
            }

            var base_item = (BaseItem) pick (x, y, DEFAULT).get_ancestor (typeof (BaseItem));
            if (base_item == current_base_item) {
                return COPY;
            }

            current_base_item = base_item;

            if (base_item != null) {
                Graphene.Point translated;
                compute_point (base_item, { (float) x, (float) y}, out translated);
                base_item.calculate_dnd_move (added_launcher, translated.x, translated.y);
            }

            return COPY;
        });

        drop_target_file.leave.connect (() => {
            current_base_item = null;

            if (added_launcher != null) {
                //Without idle it crashes when the cursor is above the launcher
                Idle.add (() => {
                    added_launcher.app.pinned = false;
                    added_launcher = null;
                    return Source.REMOVE;
                });
            }
        });

        drop_target_file.drop.connect (() => {
            if (added_launcher != null) {
                added_launcher.moving = false;
                added_launcher = null;
                return true;
            }
            return false;
        });

        AppSystem.get_default ().app_added.connect ((app) => {
            var launcher = new Launcher (app);

            if (drop_target_file.get_value () != null && added_launcher == null) { // The launcher is being added via dnd from wingpanel
                var position = (int) Math.round (drop_x / get_launcher_size ());
                added_launcher = launcher;
                launcher.moving = true;

                add_launcher_via_dnd (launcher, position);
                return;
            }

            add_item (launcher);
        });

#if WORKSPACE_SWITCHER
        WorkspaceSystem.get_default ().workspace_added.connect ((workspace) => {
            var icon_group = new WorkspaceIconGroup (workspace);
            icon_group.visible = should_show_workspace_widlet ();
            icon_group.sensitive = should_show_workspace_widlet ();
            add_item (icon_group);
        });
#endif

        map.connect (() => {
            AppSystem.get_default ().load.begin ();
            background_item.load ();
            now_playing_item.load ();
#if WORKSPACE_SWITCHER
            WorkspaceSystem.get_default ().load.begin ();
            update_workspace_widlet_state ();
            update_weather_widlet_state ();
            update_cpu_widlet_state ();
            update_ram_widlet_state ();
            update_cputemp_widlet_state ();
            update_gpu_widlet_state ();
            update_harddisk_widlet_state ();
#endif
        });
    }

    private void reposition_items () {
        var x = 0;
        foreach (var launcher in launchers) {
            position_item (launcher, ref x);
        }

        if (background_item.has_apps) {
            position_item (background_item, ref x);
        }

        if (now_playing_item.has_player) {
            position_item (now_playing_item, ref x);
        }

#if WORKSPACE_SWITCHER
        var separator_y = (get_launcher_size () - separator.height_request) / 2;
        move (separator, x - 1, separator_y);
        // Keep separator above neighboring items so it doesn't get visually covered.
        separator.insert_before (this, null);
        separator.visible = true;
#endif

#if WORKSPACE_SWITCHER
        position_widlets (ref x);
#else
        if (should_show_workspace_widlet ()) {
            foreach (var icon_group in icon_groups) {
                position_item (icon_group, ref x);
            }
        }
#endif

#if WORKSPACE_SWITCHER
        position_item (dynamic_workspace_item, ref x);
#endif
    }

    private void position_item (BaseItem item, ref int x) {
        if (item.parent != this) {
            put (item, x, 0);
            item.current_pos = x;
        } else {
            item.animate_move (x);
        }

        x += get_item_width (item);
    }

    private void add_launcher_via_dnd (Launcher launcher, int index) {
        launcher.removed.connect (remove_item);

        launchers.insert (index, launcher);
        reposition_items ();
        launcher.set_revealed (true);
        sync_pinned ();
    }

    private void add_item (BaseItem item) {
        item.removed.connect (remove_item);

        if (item is Launcher) {
            launchers.add ((Launcher) item);
            sync_pinned ();
        } else if (item is WorkspaceIconGroup) {
            var icon_group = (WorkspaceIconGroup) item;
            icon_groups.add (icon_group);
            icon_group.visible = should_show_workspace_widlet ();
            icon_group.sensitive = should_show_workspace_widlet ();
        }

        ulong reveal_cb = 0;
        reveal_cb = resize_animation.done.connect (() => {
            resize_animation.disconnect (reveal_cb);
            reposition_items ();
            item.set_revealed (true);
        });

        resize_animation.easing = EASE_OUT_BACK;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void remove_item (BaseItem item) {
        if (item is Launcher) {
            launchers.remove ((Launcher) item);
        } else if (item is WorkspaceIconGroup) {
            icon_groups.remove ((WorkspaceIconGroup) item);
        }

        item.removed.disconnect (remove_item);
        item.revealed_done.connect (remove_finish);
        item.set_revealed (false);
    }

    private void remove_finish (BaseItem item) {
        // Temporarily set the width request to avoid flicker until the animation calls the callback for the first time
        width_request = get_width ();

        remove (item);
        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_CLOSE;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();

        item.revealed_done.disconnect (remove_finish);
        item.cleanup ();
    }

    public void move_launcher_after (BaseItem source, int target_index) {
        unowned GLib.GenericArray<BaseItem>? list = null;
        double offset = 0;
        if (source is Launcher) {
            list = launchers;
        } else if (source is WorkspaceIconGroup) {
            if (!should_show_workspace_widlet ()) {
                return;
            }

            list = icon_groups;
            offset = launchers.length * get_launcher_size ();
            if (background_item.has_apps) {
                offset += get_item_width (background_item);
            }
            if (now_playing_item.has_player) {
                offset += get_item_width (now_playing_item);
            }
#if WORKSPACE_SWITCHER
            offset += get_offset_before_workspace_widlet ();
#endif
        } else {
            warning ("Tried to move neither launcher nor icon group");
            return;
        }

        if (target_index >= list.length) {
            target_index = list.length - 1;
        }

        uint source_index = 0;
        list.find (source, out source_index);

        source.animate_move ((get_launcher_size () * target_index) + offset);

        bool right = source_index > target_index;

        // Move the launchers located between the source and the target with an animation
        for (int i = (right ? target_index : (int) (source_index + 1)); i <= (right ? ((int) source_index) - 1 : target_index); i++) {
            list.get (i).animate_move ((right ? (i + 1) * get_launcher_size () : (i - 1) * get_launcher_size ()) + offset);
        }

        list.remove (source);
        list.insert (target_index, source);

        sync_pinned ();
    }

    public int get_index_for_launcher (BaseItem item) {
        if (item is Launcher) {
            uint index;
            if (launchers.find ((Launcher) item, out index)) {
                return (int) index;
            }

            return 0;
        } else if (item is WorkspaceIconGroup) {
            uint index;
            if (icon_groups.find ((WorkspaceIconGroup) item, out index)) {
                return (int) index;
            }

            return 0;
        } else if (item == dynamic_workspace_item) { //treat dynamic workspace icon as last icon group
            return (int) icon_groups.length;
        }

        warning ("Tried to get index of neither launcher nor icon group");
        return 0;
    }

    public void sync_pinned () {
        string[] new_pinned_ids = {};

        foreach (var launcher in launchers) {
            if (launcher.app.pinned) {
                new_pinned_ids += launcher.app.app_info.get_id ();
            }
        }

        settings.set_strv ("launchers", new_pinned_ids);
    }

    public void launch (uint index) {
        if (index < 1 || index > launchers.length) {
            return;
        }

        var context = Gdk.Display.get_default ().get_app_launch_context ();
        launchers.get ((int) index - 1).app.launch (context);
    }

    public static int get_launcher_size () {
        return settings.get_int ("icon-size") + Launcher.PADDING * 2;
    }

    public int get_content_width () {
        return get_total_width ();
    }

    private static int get_item_width (BaseItem item) {
        if (item is NowPlayingItem) {
            return ((NowPlayingItem) item).get_dock_width ();
        }
#if WORKSPACE_SWITCHER
        if (item is WeatherWidletItem) {
            return ((WeatherWidletItem) item).get_dock_width ();
        }
#endif

        return get_launcher_size ();
    }

    private int get_total_width () {
        var total = launchers.length * get_launcher_size ();

        if (background_item.has_apps) {
            total += get_item_width (background_item);
        }

        if (now_playing_item.has_player) {
            total += get_item_width (now_playing_item);
        }

#if WORKSPACE_SWITCHER
        total += get_widlets_total_width ();
#else
        if (should_show_workspace_widlet ()) {
            foreach (var icon_group in icon_groups) {
                total += get_item_width (icon_group);
            }
        }
#endif

#if WORKSPACE_SWITCHER
        total += get_item_width (dynamic_workspace_item);
#endif

        return total;
    }

    private bool should_show_workspace_widlet () {
#if WORKSPACE_SWITCHER
        return workspace_widlet_enabled;
#else
        return false;
#endif
    }

#if WORKSPACE_SWITCHER
    private void position_widlets (ref int x) {
        foreach (var widlet_id in get_widlet_order ()) {
            if (widlet_id == WIDLET_ID_WEATHER) {
                if (should_show_weather_widlet ()) {
                    position_item (weather_widlet_item, ref x);
                }
            } else if (widlet_id == WIDLET_ID_CPU) {
                if (should_show_cpu_widlet ()) {
                    position_item (cpu_widlet_item, ref x);
                }
            } else if (widlet_id == WIDLET_ID_RAM) {
                if (should_show_ram_widlet ()) {
                    position_item (ram_widlet_item, ref x);
                }
            } else if (widlet_id == WIDLET_ID_CPUTEMP) {
                if (should_show_cputemp_widlet ()) {
                    position_item (cputemp_widlet_item, ref x);
                }
            } else if (widlet_id == WIDLET_ID_GPU) {
                if (should_show_gpu_widlet ()) {
                    position_item (gpu_widlet_item, ref x);
                }
            } else if (widlet_id == WIDLET_ID_HARDDISK) {
                if (should_show_harddisk_widlet ()) {
                    position_item (harddisk_widlet_item, ref x);
                }
            } else if (widlet_id == WIDLET_ID_WORKSPACE) {
                if (should_show_workspace_widlet ()) {
                    foreach (var icon_group in icon_groups) {
                        position_item (icon_group, ref x);
                    }
                }
            }
        }
    }

    private int get_widlets_total_width () {
        var total = 0;

        foreach (var widlet_id in get_widlet_order ()) {
            if (widlet_id == WIDLET_ID_WEATHER) {
                if (should_show_weather_widlet ()) {
                    total += get_item_width (weather_widlet_item);
                }
            } else if (widlet_id == WIDLET_ID_CPU) {
                if (should_show_cpu_widlet ()) {
                    total += get_item_width (cpu_widlet_item);
                }
            } else if (widlet_id == WIDLET_ID_RAM) {
                if (should_show_ram_widlet ()) {
                    total += get_item_width (ram_widlet_item);
                }
            } else if (widlet_id == WIDLET_ID_CPUTEMP) {
                if (should_show_cputemp_widlet ()) {
                    total += get_item_width (cputemp_widlet_item);
                }
            } else if (widlet_id == WIDLET_ID_GPU) {
                if (should_show_gpu_widlet ()) {
                    total += get_item_width (gpu_widlet_item);
                }
            } else if (widlet_id == WIDLET_ID_HARDDISK) {
                if (should_show_harddisk_widlet ()) {
                    total += get_item_width (harddisk_widlet_item);
                }
            } else if (widlet_id == WIDLET_ID_WORKSPACE) {
                if (should_show_workspace_widlet ()) {
                    foreach (var icon_group in icon_groups) {
                        total += get_item_width (icon_group);
                    }
                }
            }
        }

        return total;
    }

    private int get_offset_before_workspace_widlet () {
        var offset = 0;

        foreach (var widlet_id in get_widlet_order ()) {
            if (widlet_id == WIDLET_ID_WORKSPACE) {
                break;
            }

            if (widlet_id == WIDLET_ID_WEATHER && should_show_weather_widlet ()) {
                offset += get_item_width (weather_widlet_item);
            } else if (widlet_id == WIDLET_ID_CPU && should_show_cpu_widlet ()) {
                offset += get_item_width (cpu_widlet_item);
            } else if (widlet_id == WIDLET_ID_RAM && should_show_ram_widlet ()) {
                offset += get_item_width (ram_widlet_item);
            } else if (widlet_id == WIDLET_ID_CPUTEMP && should_show_cputemp_widlet ()) {
                offset += get_item_width (cputemp_widlet_item);
            } else if (widlet_id == WIDLET_ID_GPU && should_show_gpu_widlet ()) {
                offset += get_item_width (gpu_widlet_item);
            } else if (widlet_id == WIDLET_ID_HARDDISK && should_show_harddisk_widlet ()) {
                offset += get_item_width (harddisk_widlet_item);
            }
        }

        return offset;
    }

    private string[] get_widlet_order () {
        string[] order = {};
        bool has_weather = false;
        bool has_cpu = false;
        bool has_ram = false;
        bool has_cputemp = false;
        bool has_gpu = false;
        bool has_harddisk = false;
        bool has_workspace = false;

        if (settings.settings_schema.has_key (WIDLET_ORDER_KEY)) {
            foreach (var raw_id in settings.get_strv (WIDLET_ORDER_KEY)) {
                var widlet_id = raw_id.strip ().down ();
                if (widlet_id == WIDLET_ID_WEATHER && !has_weather) {
                    order += WIDLET_ID_WEATHER;
                    has_weather = true;
                } else if (widlet_id == WIDLET_ID_CPU && !has_cpu) {
                    order += WIDLET_ID_CPU;
                    has_cpu = true;
                } else if (widlet_id == WIDLET_ID_CPUTEMP && !has_cputemp) {
                    order += WIDLET_ID_CPUTEMP;
                    has_cputemp = true;
                } else if (widlet_id == WIDLET_ID_RAM && !has_ram) {
                    order += WIDLET_ID_RAM;
                    has_ram = true;
                } else if (widlet_id == WIDLET_ID_GPU && !has_gpu) {
                    order += WIDLET_ID_GPU;
                    has_gpu = true;
                } else if (widlet_id == WIDLET_ID_HARDDISK && !has_harddisk) {
                    order += WIDLET_ID_HARDDISK;
                    has_harddisk = true;
                } else if (widlet_id == WIDLET_ID_WORKSPACE && !has_workspace) {
                    order += WIDLET_ID_WORKSPACE;
                    has_workspace = true;
                }
            }
        }

        if (!has_weather) {
            order += WIDLET_ID_WEATHER;
        }
        if (!has_cpu) {
            order += WIDLET_ID_CPU;
        }
        if (!has_cputemp) {
            order += WIDLET_ID_CPUTEMP;
        }
        if (!has_ram) {
            order += WIDLET_ID_RAM;
        }
        if (!has_gpu) {
            order += WIDLET_ID_GPU;
        }
        if (!has_harddisk) {
            order += WIDLET_ID_HARDDISK;
        }
        if (!has_workspace) {
            order += WIDLET_ID_WORKSPACE;
        }

        return order;
    }

    private bool should_show_weather_widlet () {
        return weather_widlet_enabled;
    }

    private bool should_show_cpu_widlet () {
        return cpu_widlet_enabled;
    }

    private bool should_show_ram_widlet () {
        return ram_widlet_enabled;
    }

    private bool should_show_cputemp_widlet () {
        return cputemp_widlet_enabled;
    }

    private bool should_show_gpu_widlet () {
        return gpu_widlet_enabled;
    }

    private bool should_show_harddisk_widlet () {
        return harddisk_widlet_enabled;
    }

    private void update_weather_widlet_state () {
        if (settings.settings_schema.has_key (WEATHER_WIDLET_KEY)) {
            weather_widlet_enabled = settings.get_boolean (WEATHER_WIDLET_KEY);
        } else {
            weather_widlet_enabled = true;
        }

        weather_widlet_item.visible = weather_widlet_enabled;
        weather_widlet_item.sensitive = weather_widlet_enabled;

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void update_cpu_widlet_state () {
        if (settings.settings_schema.has_key (CPU_WIDLET_KEY)) {
            cpu_widlet_enabled = settings.get_boolean (CPU_WIDLET_KEY);
        } else {
            cpu_widlet_enabled = true;
        }

        cpu_widlet_item.visible = cpu_widlet_enabled;
        cpu_widlet_item.sensitive = cpu_widlet_enabled;

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void update_ram_widlet_state () {
        if (settings.settings_schema.has_key (RAM_WIDLET_KEY)) {
            ram_widlet_enabled = settings.get_boolean (RAM_WIDLET_KEY);
        } else {
            ram_widlet_enabled = true;
        }

        ram_widlet_item.visible = ram_widlet_enabled;
        ram_widlet_item.sensitive = ram_widlet_enabled;

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void update_cputemp_widlet_state () {
        if (settings.settings_schema.has_key (CPUTEMP_WIDLET_KEY)) {
            cputemp_widlet_enabled = settings.get_boolean (CPUTEMP_WIDLET_KEY);
        } else {
            cputemp_widlet_enabled = true;
        }

        cputemp_widlet_item.visible = cputemp_widlet_enabled;
        cputemp_widlet_item.sensitive = cputemp_widlet_enabled;

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void update_gpu_widlet_state () {
        if (settings.settings_schema.has_key (GPU_WIDLET_KEY)) {
            gpu_widlet_enabled = settings.get_boolean (GPU_WIDLET_KEY);
        } else {
            gpu_widlet_enabled = true;
        }

        gpu_widlet_item.visible = gpu_widlet_enabled;
        gpu_widlet_item.sensitive = gpu_widlet_enabled;

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void update_harddisk_widlet_state () {
        if (settings.settings_schema.has_key (HARDDISK_WIDLET_KEY)) {
            harddisk_widlet_enabled = settings.get_boolean (HARDDISK_WIDLET_KEY);
        } else {
            harddisk_widlet_enabled = true;
        }

        harddisk_widlet_item.visible = harddisk_widlet_enabled;
        harddisk_widlet_item.sensitive = harddisk_widlet_enabled;

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }

    private void update_workspace_widlet_state () {
        if (settings.settings_schema.has_key (WORKSPACE_WIDLET_KEY)) {
            workspace_widlet_enabled = settings.get_boolean (WORKSPACE_WIDLET_KEY);
        } else {
            workspace_widlet_enabled = true;
        }

        foreach (var icon_group in icon_groups) {
            icon_group.visible = workspace_widlet_enabled;
            icon_group.sensitive = workspace_widlet_enabled;
        }

        reposition_items ();

        resize_animation.easing = EASE_IN_OUT_QUAD;
        resize_animation.duration = Granite.TRANSITION_DURATION_OPEN;
        resize_animation.value_from = get_width ();
        resize_animation.value_to = get_total_width ();
        resize_animation.play ();
    }
#endif
}
