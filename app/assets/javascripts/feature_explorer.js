(function () {
  if (window.__ogExplorerBound) return;
  window.__ogExplorerBound = true;

  var KEYS = {
    collapsed: "og.explorer.collapsed",
    width: "og.explorer.width",
    folders: "og.explorer.folders"
  };

  function explorer() {
    return document.querySelector("[data-explorer]");
  }

  function htmlRoot() {
    return document.documentElement;
  }

  function readFolders() {
    try {
      return JSON.parse(localStorage.getItem(KEYS.folders) || "{}");
    } catch (error) {
      return {};
    }
  }

  function writeFolders(map) {
    localStorage.setItem(KEYS.folders, JSON.stringify(map));
  }

  function applyCollapsed(collapsed) {
    var root = explorer();
    if (!root) return;

    root.classList.toggle("is-collapsed", collapsed);
    htmlRoot().classList.toggle("explorer-collapsed", collapsed);
    localStorage.setItem(KEYS.collapsed, collapsed ? "1" : "0");
  }

  function applyWidth(width) {
    var next = Math.min(360, Math.max(220, width));
    document.documentElement.style.setProperty("--fx-width", next + "px");
    localStorage.setItem(KEYS.width, String(next));
  }

  function restoreState() {
    var root = explorer();
    if (!root) return;

    var storedWidth = parseInt(localStorage.getItem(KEYS.width) || "", 10);
    if (!isNaN(storedWidth)) applyWidth(storedWidth);

    var collapsed = localStorage.getItem(KEYS.collapsed) === "1";
    if (window.matchMedia("(max-width: 860px)").matches) {
      collapsed = false;
      root.classList.remove("is-open-mobile");
    }
    applyCollapsed(collapsed);

    var folders = readFolders();
    root.querySelectorAll("[data-explorer-folder]").forEach(function (folder) {
      var id = folder.getAttribute("data-explorer-folder");
      var hasActive = folder.classList.contains("is-active-group");
      var stored = folders[id];
      var isOpen = hasActive || stored !== false;
      if (typeof stored === "boolean" && !hasActive) isOpen = stored;
      folder.classList.toggle("is-open", isOpen);
      var button = folder.querySelector("[data-explorer-folder-btn]");
      if (button) button.setAttribute("aria-expanded", isOpen ? "true" : "false");
    });
  }

  function toggleFolder(folder) {
    var next = !folder.classList.contains("is-open");
    folder.classList.toggle("is-open", next);
    var button = folder.querySelector("[data-explorer-folder-btn]");
    if (button) button.setAttribute("aria-expanded", next ? "true" : "false");
    var folders = readFolders();
    folders[folder.getAttribute("data-explorer-folder")] = next;
    writeFolders(folders);
  }

  function filterTree(query) {
    var root = explorer();
    if (!root) return;

    var needle = query.trim().toLowerCase();
    var visibleCount = 0;

    root.querySelectorAll("[data-explorer-folder]").forEach(function (folder) {
      var folderMatch = false;

      folder.querySelectorAll("[data-explorer-item]").forEach(function (item) {
        var haystack = (item.getAttribute("data-search") || "").toLowerCase();
        var show = !needle || haystack.indexOf(needle) !== -1;
        item.classList.toggle("is-hidden", !show);
        if (show) {
          folderMatch = true;
          visibleCount += 1;
        }
      });

      folder.classList.toggle("is-hidden", needle.length > 0 && !folderMatch);
      if (needle && folderMatch) folder.classList.add("is-open");
    });

    var empty = root.querySelector("[data-explorer-empty]");
    if (empty) empty.classList.toggle("is-visible", needle.length > 0 && visibleCount === 0);
  }

  function setMobileOpen(open) {
    var root = explorer();
    var backdrop = document.querySelector("[data-explorer-backdrop]");
    if (!root) return;
    root.classList.toggle("is-open-mobile", open);
    if (backdrop) backdrop.classList.toggle("is-visible", open);
  }

  function startResize(event) {
    var root = explorer();
    if (!root || root.classList.contains("is-collapsed")) return;
    if (window.matchMedia("(max-width: 860px)").matches) return;

    event.preventDefault();
    var startX = event.clientX;
    var startWidth = root.getBoundingClientRect().width;

    function onMove(moveEvent) {
      applyWidth(startWidth + (moveEvent.clientX - startX));
    }

    function onUp() {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    }

    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  }

  document.addEventListener("click", function (event) {
    var toggle = event.target.closest("[data-explorer-toggle]");
    if (toggle) {
      var root = explorer();
      if (!root) return;
      if (window.matchMedia("(max-width: 860px)").matches) {
        setMobileOpen(!root.classList.contains("is-open-mobile"));
        return;
      }
      applyCollapsed(!root.classList.contains("is-collapsed"));
      return;
    }

    var folderBtn = event.target.closest("[data-explorer-folder-btn]");
    if (folderBtn) {
      var folder = folderBtn.closest("[data-explorer-folder]");
      if (folder) toggleFolder(folder);
      return;
    }

    var railBtn = event.target.closest("[data-explorer-rail]");
    if (railBtn) {
      var folderId = railBtn.getAttribute("data-explorer-rail");
      applyCollapsed(false);
      var folder = document.querySelector('[data-explorer-folder="' + folderId + '"]');
      if (folder) {
        folder.classList.add("is-open");
        var folders = readFolders();
        folders[folderId] = true;
        writeFolders(folders);
      }
      return;
    }

    var backdrop = event.target.closest("[data-explorer-backdrop]");
    if (backdrop) setMobileOpen(false);

    var item = event.target.closest("[data-explorer-item]");
    if (item && window.matchMedia("(max-width: 860px)").matches) {
      setMobileOpen(false);
    }
  });

  document.addEventListener("input", function (event) {
    if (event.target.matches("[data-explorer-search]")) {
      filterTree(event.target.value);
    }
  });

  document.addEventListener("mousedown", function (event) {
    if (event.target.closest("[data-explorer-resize]")) startResize(event);
  });

  document.addEventListener("keydown", function (event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "b") {
      var root = explorer();
      if (!root) return;
      event.preventDefault();
      if (window.matchMedia("(max-width: 860px)").matches) {
        setMobileOpen(!root.classList.contains("is-open-mobile"));
      } else {
        applyCollapsed(!root.classList.contains("is-collapsed"));
      }
    }

    if (event.key === "Escape") setMobileOpen(false);
  });

  function boot() {
    if (!explorer()) return;
    htmlRoot().classList.add("has-explorer");
    restoreState();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  document.addEventListener("turbo:load", boot);
})();
