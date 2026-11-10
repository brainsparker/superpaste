import { test, expect } from "vitest";
import { readFileSync } from "node:fs";
import vm from "node:vm";

function page() {
  const handlers:Record<string,()=>void>={};
  const nodes=new Map<string,ReturnType<typeof node>>();
  function node() { return { textContent:"", className:"", disabled:false, style:{}, classList:{add(){},remove(){}}, appendChild(){}, addEventListener(type:string,fn:()=>void){handlers[type]=fn;} }; }
  const pending:Array<(response:unknown)=>void>=[];
  const copied:string[]=[];
  const location={hash:"#c=v1.A",origin:"https://superpaste.ai",pathname:"/share",href:"https://superpaste.ai/share#c=v1.A"};
  const context={location,URLSearchParams,Date,encodeURIComponent,
    document:{getElementById(id:string){if(!nodes.has(id))nodes.set(id,node());return nodes.get(id);},createElement:node},
    navigator:{clipboard:{writeText:async(text:string)=>{copied.push(text);}}},
    window:{addEventListener(type:string,fn:()=>void){handlers[type]=fn;}},
    fetch:()=>new Promise(resolve=>pending.push(resolve)),
  };
  const source=readFileSync(new URL("../../website/share.html",import.meta.url),"utf8").match(/<script>([\s\S]*?)<\/script>/)![1]!;
  vm.runInNewContext(source,context);
  return {handlers,nodes,pending,copied,location};
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
const success=(name:string)=>({ok:true,json:async()=>({campaign:{name,intent:name,requiredFacts:[]},platforms:[]})});
test("fragment changes invalidate copy and discard older resolutions",async()=>{
  const p=page();
  p.location.hash="#c=v1.B";p.location.href="https://superpaste.ai/share#c=v1.B";p.handlers.hashchange!();
  expect(p.nodes.get("copy")!.disabled).toBe(true);
  p.handlers.click!();await flush();expect(p.copied).toEqual([]);
  p.pending[0]!(success("Campaign A"));await flush();expect(p.nodes.get("campaign-name")?.textContent).not.toBe("Campaign A");
  p.pending[1]!(success("Campaign B"));await flush();expect(p.nodes.get("campaign-name")!.textContent).toBe("Campaign B");
  p.handlers.click!();await flush();expect(p.copied).toEqual(["https://superpaste.ai/share#c=v1.B"]);
  p.location.hash="#c=invalid";p.handlers.hashchange!();expect(p.nodes.get("copy")!.disabled).toBe(true);
  p.pending[2]!({ok:false,json:async()=>({error:"invalid_link"})});await flush();p.handlers.click!();await flush();expect(p.copied).toHaveLength(1);
});
