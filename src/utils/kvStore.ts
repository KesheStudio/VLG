import { computed } from "vue"
import { storeToRefs } from "pinia";
import { useKVStore } from "@/stores/kv";


export const getKV = (k:string) =>{
  const kv = useKVStore();
  const { map } = storeToRefs(kv);
  return computed(
    () => map.value[k] as string | undefined,
  );
}