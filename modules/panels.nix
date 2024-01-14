{ config, lib, ... }:

with lib;

let
  cfg = config.programs.plasma;
  panelType = lib.types.submodule {
    options = {
      height = lib.mkOption {
        type = lib.types.int;
        default = 32;
        description = "The height of the panel.";
      };
      offset = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 100;
        description = "The offset of the panel from the anchor-point.";
      };
      minLength = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 1000;
        description = "The minimum required length/width of the panel.";
      };
      maxLength = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 1600;
        description = "The maximum allowed length/width of the panel.";
      };
      location = lib.mkOption {
        type = lib.types.str;
        default = lib.types.nullOr (lib.types.enum [ "top" "bottom" "left" "right" "floating" ]);
        example = "left";
        description = "The location of the panel.";
      };
      alignment = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "left" "center" "right" ]);
        default = "center";
        example = "right";
        description = "The alignment of the panel.";
      };
      hiding = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "none" "autohide" "windowscover" "windowsbelow" ]);
        default = null;
        example = "autohide";
        description = "The hiding mode of the panel.";
      };
      widgets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.pager"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marignsseperator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
        example = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marignsseperator"
          "org.kde.plasma.digitalclock"
        ];
        description = ''
          The widgets to use in the panel. To get the names, it may be useful
          to look in the share/plasma/plasmoids folder of the nix-package the
          widget/plasmoid is from. Some packages which include some
          widgets/plasmoids are for example plasma-desktop and
          plasma-workspace.
        '';
      };
      iconTasksLaunchers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "org.kde.dolphin.desktop"
          "firefox.desktop"
        ];
        description = ''
          The desktop-files to pin to the icontasks task-manager. For this to
          have any effect, org.kde.plasma.icontasks must be included in the
          widgets option.
        '';
      };
      extraSettings = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Extra lines to add to the layout.js. See
          https://develop.kde.org/docs/plasma/scripting/ for inspiration.
        '';
      };
    };
  };

  # The value of the config for the org.kde.plasma.icontasks plasmoid must be a
  # list on the form applications:{{name of application 1}}.desktop,
  # applications:{{name of application 2}}.desktop,..., hence we just transform
  # it this way here.
  iconTasksLaunchersStr = iconTasksLaunchers: "[${lib.concatStringsSep "," (map (p: "\"applications:${p}\"") iconTasksLaunchers)}]";

  # Creates lines for changing the config of a widget in a layout.js. Here
  # panel is the panel of the widget we are configuring for, widget is the full
  # name of the widget, configGroup is the value of currentConfigGroup for the
  # widget, while configKey and value are the key and value we want to set.
  panelModifyConfig = panel: widget: configGroup: configKey: value:
    if builtins.elem widget panel.widgets then ''
      var w = panelWidgets["${widget}"]
      w.currentConfigGroup = ${configGroup}
      w.writeConfig("${configKey}", ${value})
    '' else "";

  # Functions to aid us creating a single panel in the layout.js
  panelAddWidgetStr = widget: "panelWidgets[\"${widget}\"] = panel.addWidget(\"${widget}\")";
  panelAddWidgetsStr = panel: lib.concatStringsSep "\n" (map panelAddWidgetStr panel.widgets);
  panelToLayout = panel: ''

    var panel = new Panel;
    panel.height = ${builtins.toString panel.height}
    var panelWidgets = {}
    ${if panel.alignment != null then "panel.alignment = \"${panel.alignment}\"" else ""}
    ${if panel.hiding != null then "panel.hiding = \"${panel.hiding}\"" else ""}
    ${if panel.location != null then "panel.location = \"${panel.location}\"" else ""}
    ${if panel.maxLength != null then "panel.maximumLength = ${builtins.toString panel.maxLength}" else ""}
    ${if panel.minLength != null then "panel.minimumLength = ${builtins.toString panel.minLength}" else ""}
    ${if panel.offset != null then "panel.offset = ${builtins.toString panel.offset}" else ""}
    ${panelAddWidgetsStr panel}
    ${if builtins.length panel.iconTasksLaunchers > 0 then
      (panelModifyConfig
        panel "org.kde.plasma.icontasks" "[\"General\"]"
        "launchers" (iconTasksLaunchersStr panel.iconTasksLaunchers))
      else ""}
    ${if panel.extraSettings != null then panel.extraSettings else ""}
  '';

  # Generates the text for the full layout.js, combining the configuration for
  # all the single panels into one.
  panelsToLayoutJS = panels: lib.concatStringsSep "\n" (map panelToLayout panels);
in
{
  options.programs.plasma.panels = lib.mkOption {
    type = lib.types.listOf panelType;
    default = [ ];
  };

  config = mkIf (cfg.enable && (lib.length cfg.panels) > 0) {
    programs.plasma.startup.dataFile."layout.js" = ''
      // Removes all existing panels
      var allPanels = panels();
      for (var panelIndex = 0; panelIndex < allPanels.length; panelIndex++) {
        var p = allPanels[panelIndex];
        p.remove();
      }

      // Adds the panels
      ${panelsToLayoutJS config.programs.plasma.panels}
    '';
    programs.plasma.startup.autoStartScript."apply_layout" = ''
      layout_file="${config.xdg.dataHome}/plasma-manager/${config.programs.plasma.startup.dataDir}/layout.js"
      last_update=$(stat -c %Y $layout_file)
      last_update_file=${config.xdg.dataHome}/plasma-manager/last_update_layouts
      stored_last_update=0
      if [ -f "$last_update_file" ]; then
        stored_last_update=$(cat "$last_update_file")
      fi

      [ $last_update -gt $stored_last_update ] && \
      qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat $layout_file)" && \
      echo "$last_update" > "$last_update_file"
    '';
  };
}