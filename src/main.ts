import { createApp } from "vue";
import App from "./App.vue";
import router from "./router/index.ts";
import "./styles/variable.scss";

const app = createApp(App);

app.use(router);

app.mount("#app");
