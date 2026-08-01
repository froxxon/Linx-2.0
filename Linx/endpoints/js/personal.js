  // Send with RequestArg when changing private Theme
  function SetTheme(theme){location.href = "/?SelectTheme&" + theme + "&Personal";}

  document.addEventListener("DOMContentLoaded", () => {
    const btnRemoveLink = document.getElementById("btnRemoveLink");
    if ( btnRemoveLink ) { btnRemoveLink.addEventListener("click", function() { window.location.href="/Personal"; }); }
  });