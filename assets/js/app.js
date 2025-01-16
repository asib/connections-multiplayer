// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { createPopper } from '@popperjs/core';
import gsap from "gsap";
import textFit from "textfit";

const confetti = require('canvas-confetti');

var count = 200;
var defaults = {
  origin: { y: 0.7 }
};

window.addEventListener("phx:fire-confetti-cannon", () => {
  fire(0.25, {
    spread: 26,
    startVelocity: 55,
  });
  fire(0.2, {
    spread: 60,
  });
  fire(0.35, {
    spread: 100,
    decay: 0.91,
    scalar: 0.8
  });
  fire(0.1, {
    spread: 120,
    startVelocity: 25,
    decay: 0.92,
    scalar: 1.2
  });
  fire(0.1, {
    spread: 120,
    startVelocity: 45,
  });
});

function fire(particleRatio, opts) {
  confetti({
    ...defaults,
    ...opts,
    particleCount: Math.floor(count * particleRatio),
    disableForReducedMotion: true,
  });
}

const Hooks = {};

class Tooltip {
  showEvents = ['mouseenter', 'focus'];
  hideEvents = ['mouseleave', 'blur'];
  $parent;
  $tooltip;
  popperInstance;

  constructor($tooltip) {
    this.$tooltip = $tooltip;
    this.$parent = $tooltip.parentElement;
    this.popperInstance = createPopper(this.$parent, $tooltip, {
      modifiers: [
        {
          name: 'offset',
          options: {
            offset: [0, 8],
          },
        },
      ],
    });
    this.destructors = [];

    // For each show event, add an event listener on the parent element
    //   and store a destructor to call removeEventListener
    //   when the tooltip is destroyed.
    this.showEvents.forEach((event) => {
      const callback = this.show.bind(this);
      this.$parent.addEventListener(event, callback);
      this.destructors.push(() =>
        this.$parent.removeEventListener(event, callback)
      );
    });

    // For each hide event, add an event listener on the parent element
    //   and store a destructor to call removeEventListener
    //   when the tooltip is destroyed.
    this.hideEvents.forEach((event) => {
      const callback = this.hide.bind(this);
      this.$parent.addEventListener(event, callback);
      this.destructors.push(() =>
        this.$parent.removeEventListener(event, callback)
      );
    });
  }

  // The show method adds the data-show attribute to the tooltip element,
  //   which makes it visible (see CSS).
  show() {
    this.$tooltip.setAttribute('data-show', '');
    this.update();
  }

  // Update the popper instance so the tooltip position is recalculated.
  update() {
    this.popperInstance?.update();
  }

  // The hide method removes the data-show attribute from the tooltip element,
  //   which makes it invisible (see CSS).
  hide() {
    this.$tooltip.removeAttribute('data-show');
  }

  // The destroy method removes all event listeners
  //   and destroys the popper instance.
  destroy() {
    this.destructors.forEach((destructor) => destructor());
    this.popperInstance?.destroy();
  }
}

Hooks.TooltipHook = {
  mounted() {
    this.el.tooltip = new Tooltip(this.el);
  },
  updated() {
    this.el.tooltip?.update();
  },
  destroyed() {
    this.el.tooltip?.destroy();
  },
}


Hooks.ShareButton = {
  mounted() {
    const shareData = {
      url: window.location.href,
    }

    this.el.addEventListener("click", async () => {
      if (typeof navigator.share === "function" && window.matchMedia('(max-device-width: 768px)').matches) {
        await navigator.share(shareData)
      } else {
        await navigator.clipboard.writeText(shareData.url).catch((e) => console.error(e))

        const preClickContent = document.querySelector("#share-game-link-button-pre-click-content");
        const postClickContent = document.querySelector("#share-game-link-button-post-click-content");

        preClickContent.classList.add("hidden")
        preClickContent.classList.remove("inline-flex")

        postClickContent.classList.remove("hidden")
        postClickContent.classList.add("inline-flex")
      }
    });
  }
}

Hooks.Avatar = {
  mounted() {
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      const el = document.querySelector(`#${this.el.id}>div`)

      const tl = gsap.timeline({ paused: true, defaults: { ease: "power1.out" } });
      tl.to(el, { scale: 1.1, duration: 0.3, onComplete: () => console.log("scaled") })
      tl.add("afterScale")
      tl.to(el, { rotation: 25, duration: 0.5 })
      tl.to(el, { rotation: -25, duration: 1 })
      tl.to(el, { rotation: 0, duration: 0.5 })
      tl.add("end")

      const tl2 = gsap.timeline({ paused: true })
      tl2.add(tl.tweenFromTo(0, "afterScale"))
      tl2.add(tl.tweenFromTo("afterScale", "end", { repeat: -1 }))

      this.el.addEventListener("mouseenter", () => {
        tl2.play(0)
      })
      this.el.addEventListener("mouseleave", () => {
        tl2.pause()
        gsap.to(el, { scale: 1, rotation: 0, duration: 0.3 })
      })
    }
  },
}

Hooks.CardButton = {
  mounted() {
    function fitText(el) {
      textFit(el, { maxFontSize: 16, multiLine: true })
    }

    const el = this.el.querySelector(`#card-button-text-${this.el.id}`)

    fitText(el);

    const resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        fitText(entry.target)
      }
    });

    const mutationObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          fitText(mutation.target);
        }
      }
    });

    resizeObserver.observe(el);
    mutationObserver.observe(el, { childList: true });

    this.handleEvent(`animate-hint-${this.el.id}`, () => {
      gsap.fromTo(this.el, { rotate: 15 }, { rotation: 0, ease: "elastic.out(1.2,0.1)", duration: 2 })
    });
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket