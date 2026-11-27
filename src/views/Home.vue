<script lang="ts" setup>
import type { Settings } from "@/types/config/settings";
import type { InitConfig } from "@/types/config/init";
import { onMounted, ref } from "vue";
import { playFadeInOut } from "@/utils/animations";
import { AudioPlayer } from "@/utils/audioPlayer";
import { FileAPI } from "@/utils/fileAPI";
import { getKV } from "@/utils/kvStore";

const TContent = ref<HTMLImageElement>();
const backgroundImage = getKV("mainBackgroundImageUrl");

const playGameImage = getKV("playGameImage");
const loadSaveImage = getKV("loadSaveImage");
const unlockedResourcesImage = getKV("unlockedResourcesImage");
const gameSettingsImage = getKV("gameSettingsImage");
const sideStoryImage = getKV("sideStoryImage");
const exitGameImage = getKV("exitGameImage");

const init = async (): Promise<void> => {
  if (!TContent.value) {
    console.warn("[Audio] Home view mounted without TContent element.");
    return;
  }

  try {
    const settings = await FileAPI.readConfig<Settings>("config/settings.json");
    const initConfig = await FileAPI.readConfig<InitConfig>("config/mainPage.json");
    const music = settings?.audio?.music;

    if (music?.isPlay) {
      if (!initConfig?.backgroundMusic) {
        throw new Error("config/mainPage.json: backgroundMusic is empty.");
      }
      const volume = music.volume ?? 1;
      if (music.isFadePlay) {
        AudioPlayer.bgm.fadePlay(
          initConfig.backgroundMusic,
          music.fadeTime ?? 1000,
          { startingVolume: 0, targetVolume: volume },
        );
      } else {
        await AudioPlayer.bgm.setVolume(volume);
        await AudioPlayer.bgm.play(initConfig.backgroundMusic);
      }
    } else {
      console.info("[Audio] BGM is disabled in settings.json.");
    }
  } catch (error) {
    console.error("[Audio] BGM startup failed:", error);
  }

  await playFadeInOut(TContent.value, {
    duration: 1500,
    autoHide: false,
  });
};

onMounted(async () => {
  await init();
});
</script>

<template>
  <div class="TContent" ref="TContent">
    <img
      v-if="backgroundImage"
      :src="backgroundImage"
      alt="background"
      class="background"
    />
    <div class="menu">
      <div class="button">
        <img :src="playGameImage">
      </div>
      <div class="button">
        <img :src="loadSaveImage">
      </div>
      <div class="button">
        <img :src="unlockedResourcesImage">
      </div>
      <div class="button">
        <img :src="gameSettingsImage">
      </div>
      <div class="button">
        <img :src="sideStoryImage">
      </div>
      <div class="button">
        <img :src="exitGameImage">
      </div>
    </div>
  </div>
</template>
<style lang="scss" scoped>
.TContent {
  width: 100%;
  height: 100%;
  position: relative;
  opacity: 0;
}

.background{
  height: 100%;
  position: absolute;
  top: 0;
  left: 0;
  z-index: -1;
}

.menu {
  position: absolute;
  left: 3%;
  bottom: 3%;
  display: flex;
  flex-direction: column;
  height: 50%;
  align-items: flex-start;
  justify-content: flex-start;

  .button {
    height: calc(100% / 6);
    display: flex;
    align-items: center;
    justify-content: flex-start;
    width: auto;

    img {
      height: 100%;
      width: auto;
      object-fit: contain;
      cursor: pointer;
    }
  }
}
</style>