    // Send with RequestArg when changing private Theme
    function SetTheme(theme){location.href = "/?SelectTheme&" + theme + "&Admin";}

    // Send with RequestArg what Theme to edit
    function ChooseThemeToEdit(theme){location.href = "/Admin?CSS&" + theme;}

    function enableDisableFields() {    
        if (document.getElementById('chkPersonal').checked) {
            document.getElementsByName('Role')[0].disabled = true;
            document.getElementsByName('Contact')[0].disabled = true;
        }
        else {
            document.getElementsByName('Role')[0].disabled = false;
            document.getElementsByName('Contact')[0].disabled = false;
        }
    }

    // filter log page
    function filterFunctionLogTable() {
      var input, filter, table, tr, td, i,alltables;
      alltables = document.querySelectorAll("table[data-name=mytable]");
      input = document.getElementById("inputFilterLog");
      filter = input.value.toUpperCase();
      alltables.forEach(function(table){
        tr = table.getElementsByTagName("tr");
        for (i = 0; i < tr.length; i++) {
          td = tr[i].getElementsByTagName("td")[0];
          if (td) {
            if (td.innerHTML.toUpperCase().indexOf(filter) > -1) {
              tr[i].style.display = "";
            } else {
              tr[i].style.display = "none";
            }
          }       
        }
      });
    }

  document.addEventListener("DOMContentLoaded", () => {
    const inputLog = document.getElementById("inputFilterLog");
    if ( inputLog ) {
      inputLog.addEventListener("keyup", filterFunctionLogTable);
    }
    const btnRemoveLink = document.getElementById("btnRemoveLink");
    if ( btnRemoveLink ) { btnRemoveLink.addEventListener("click", function() { window.location.href="/" }); }
    const btnCancel = document.getElementById("btnCancel");
    if ( btnCancel ) { btnCancel.addEventListener("click", function() { window.location.href="/" }); }

    const chkPersonal = document.getElementById("chkPersonal");
    if ( chkPersonal ) { chkPersonal.addEventListener("click", function() { enableDisableFields(); }); }

    const btnChooseLogo = document.getElementById("btnChooseLogo");
    if ( btnChooseLogo ) { btnChooseLogo.addEventListener("click", function() { document.getElementById("filLogo").click(); }); }
  });

  var handleFileSelect = function(evt) {
  if (handleFileSelect) {
    var files = evt.target.files;
    var file = files[0];
    if (files && file) {
      var reader = new FileReader();
      reader.onload = function(readerEvt) {
        var binaryString = readerEvt.target.result;
        document.getElementById("base64area").value = btoa(binaryString);
        document.getElementById("tempLogo").src = "data:image/png;base64," + btoa(binaryString);
      };
      reader.readAsBinaryString(file);
    }
  };
  if (window.File && window.FileReader && window.FileList && window.Blob) {
    document.getElementById('filLogo').addEventListener('change', handleFileSelect, false);
  } else { alert('The File APIs are not fully supported in this browser.'); }
  }