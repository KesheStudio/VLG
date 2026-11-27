import { createApp } from "vue";
import App from "./App.vue";
import router from "./router/index.ts";
import "./styles/variable.scss";
import { createPinia } from "pinia";

const app = createApp(App);

app.use(router);
app.use(createPinia());

app.mount("#app");

const prevent = (event: Event): void => {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
};

document.addEventListener("dragstart", prevent, true);
document.addEventListener("drag", prevent, true);
document.addEventListener("dragend", prevent, true);

document.addEventListener("dragenter", prevent, true);
document.addEventListener("dragover", prevent, true);
document.addEventListener("drop", prevent, true);

document.addEventListener(
  "contextmenu",
  (event) => {
    event.preventDefault();
    event.stopPropagation();
  },
  true,
);
