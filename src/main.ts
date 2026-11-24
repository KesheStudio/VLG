import { createApp } from "vue";
import App from "./App.vue";
import router from "./router/index.ts";
import "./styles/variable.scss";
import "./styles/globa.scss"

const app = createApp(App);

app.use(router);

app.mount("#app");