<script lang="ts" setup>
import { onMounted, ref } from 'vue';
import { FileAPI } from './utils/FileAPI';

interface initConfig {
  title:string;
  backgroundImage:string;
  loadingImage:string;
  backgroundMusic:string;
}

const loadingImage = ref()

const init = async ():Promise<void> => {
  const config = await FileAPI.readConfig<initConfig>("config/mainPage.json");
  console.log(config)
  loadingImage.value = await (await FileAPI.readAsBlobUrl(config.loadingImage)).url
  console.log(loadingImage.value)
}

onMounted(()=>{
  init()
})

</script>

<template>
  <div class="TopBox">
    <img :src="loadingImage" alt="">
  </div>
</template>

<style lang="scss" scoped>
.TopBox {
  aspect-ratio: 16 / 9;
  width: 100vw;
  max-height: 100vh;
  max-width: calc(100vh * 16 / 9);
  & > *{
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
}
</style>