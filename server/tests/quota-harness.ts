import { QuotaLedger } from "../src/quota.ts";

/** Serial transactional storage double. Tests run the production ledger, not a copied limiter. */
export function quotaNamespace(initial: Record<string,number> = {}) {
  const store = new Map<string,unknown>(Object.entries(initial));
  let tail: Promise<unknown> = Promise.resolve();
  const tx = {
    get: async <T>(key:string):Promise<T|undefined> => store.get(key) as T|undefined,
    put: async (key:string|Record<string,unknown>,value?:unknown) => {
      if (typeof key === "string") store.set(key,value);
      else for (const [k,v] of Object.entries(key)) store.set(k,v);
    },
  };
  const state = { storage: { transaction: <T>(callback:(txn:typeof tx)=>Promise<T>) => {
    const result = tail.then(async () => {
      const before = new Map(store);
      try { return await callback(tx); }
      catch (error) { store.clear(); for(const [k,v] of before) store.set(k,v); throw error; }
    });
    tail = result.then(()=>{},()=>{});
    return result;
  } } } as unknown as DurableObjectState;
  const ledger = new QuotaLedger(state);
  const namespace = {
    idFromName: (name:string) => name,
    get: () => ({ fetch: (input: string|Request, init?:RequestInit) => ledger.fetch(new Request(input,init)) }),
  } as unknown as DurableObjectNamespace;
  return { namespace, store, ledger };
}
