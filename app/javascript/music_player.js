function createYoutubePlayers() {
  document.querySelectorAll("[data-yt-playlist]").forEach(function (el) {
    new YT.Player(el, {
      height: "152",
      width: "100%",
      playerVars: {
        listType: "playlist",
        list: el.dataset.ytPlaylist,
        autoplay: 0,
        rel: 0,
      },
      events: {
        onReady: function (event) {
          const playlist = event.target.getPlaylist();
          const length = playlist && playlist.length > 0 ? playlist.length : 30;
          const idx = Math.floor(Math.random() * length);
          event.target.cuePlaylist({
            listType: "playlist",
            list: el.dataset.ytPlaylist,
            index: idx,
          });
        },
      },
    });
  });
}

function initYoutubePlayers() {
  if (!document.querySelector("[data-yt-playlist]")) return;

  if (window.YT && window.YT.Player) {
    // API already loaded (e.g. Turbo navigation) — init directly
    createYoutubePlayers();
  } else {
    // Set callback for when the API finishes loading
    window.onYouTubeIframeAPIReady = createYoutubePlayers;
    // Only inject the script once
    if (!document.querySelector('script[src="https://www.youtube.com/iframe_api"]')) {
      const tag = document.createElement("script");
      tag.src = "https://www.youtube.com/iframe_api";
      document.head.appendChild(tag);
    }
  }
}

// turbo:load fires on both initial page load and Turbo navigations
document.addEventListener("turbo:load", initYoutubePlayers);
