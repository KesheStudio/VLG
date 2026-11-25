import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useKVStore = defineStore('kv', () => {
  const map = ref<Record<string, unknown>>({});

  function set<T>(key: string, value: T) {
    map.value[key] = value;
  }

  function get<T>(key: string): T | undefined {
    return map.value[key] as T | undefined;
  }

  function remove(key: string) {
    delete map.value[key];
  }

  function clear() {
    map.value = {};
  }

  function has(key: string): boolean {
    return key in map.value;
  }

  return { map, set, get, remove, clear, has };
});