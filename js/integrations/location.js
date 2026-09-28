// TODO: CONNECT REAL GPS LATER
// TODO: CONNECT NOMINATIM REVERSE GEOCODING LATER
export const getMockLocation=()=>({lat:'18.3925',lng:'77.1153',address:'Main Road, Udgir'});

export const getCurrentLocation=()=>new Promise(resolve=>{
  if(!navigator.geolocation)return resolve({lat:null,lng:null,address:null});
  navigator.geolocation.getCurrentPosition(
    position=>resolve({lat:position.coords.latitude,lng:position.coords.longitude,address:null}),
    ()=>resolve({lat:null,lng:null,address:null}),
    {enableHighAccuracy:true,timeout:8000,maximumAge:60000}
  );
});
