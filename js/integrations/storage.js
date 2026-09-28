// TODO: CONNECT SUPABASE STORAGE LATER
export const storage={get:(key,fallback)=>{try{return JSON.parse(localStorage.getItem(key))??fallback}catch{return fallback}},set:(key,value)=>localStorage.setItem(key,JSON.stringify(value))};
