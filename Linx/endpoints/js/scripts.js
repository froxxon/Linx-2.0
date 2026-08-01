    function filterFunctionMultiTables() {
      var input, filter, table, tr, td, i,alltables;
      alltables = document.querySelectorAll("table[data-name=mytable]");
      input = document.getElementById("inputFilter");
      filter = input.value.toUpperCase();
      alltables.forEach(function(table){
      tr = table.getElementsByTagName("tr");
        for (i = 0; i < tr.length; i++) {
          td = tr[i].getElementsByTagName("td")[2];
            if (td) {
              if (td.innerHTML.toUpperCase().indexOf(filter) > -1) {
                tr[i].style.display = "";
              } else {
                tr[i].style.display = "none";
              }
            }       
          }
        }
      );
    }
    const themeSelect = document.getElementById('themeSelect');    
    if ( themeSelect ) {
      themeSelect.addEventListener('change', function() {
        const theme = this.value;
        location.href = "/?SelectTheme&" + theme + "&";
      });
    }

  document.addEventListener("DOMContentLoaded", () => {
    const inputFilter = document.getElementById("inputFilter");
    if ( inputFilter ) {
      inputFilter.addEventListener("keyup", filterFunctionMultiTables);
    }
    const formAutoSubmit = document.getElementById("AutoSubmit");
    if ( formAutoSubmit ) { formAutoSubmit.submit(); }

  });

    function sortTable(n) {
      var table, rows, switching, i, x, y, shouldSwitch, dir, switchcount = 0;
      table = document.getElementById("filteredTable");
      switching = true;
      dir = "asc";
      while (switching) {
        switching = false;
        rows = table.rows;
        for (i = 1; i < (rows.length - 1); i++) {
          shouldSwitch = false;
          x = rows[i].getElementsByTagName("TD")[n];
          y = rows[i + 1].getElementsByTagName("TD")[n];
          if (dir == "asc") {
            if (x.innerHTML.toLowerCase() > y.innerHTML.toLowerCase()) {
              shouldSwitch = true;
              break;
            }
          } else if (dir == "desc") {
            if (x.innerHTML.toLowerCase() < y.innerHTML.toLowerCase()) {
              shouldSwitch = true;
              break;
            }
          }
        }
        if (shouldSwitch) {
          rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
          switching = true;
          switchcount ++;
        } else {
          if (switchcount == 0 && dir == "asc") {
            dir = "desc";
            switching = true;
          }
        }
      }
    }

    function sortTableByAREF(n) {
      var table, rows, switching, i, x, y, shouldSwitch, dir, switchcount = 0;
      table = document.getElementById("filteredTable");
      switching = true;
      dir = "asc";
      while (switching) {
        switching = false;
        rows = table.rows;
        for (i = 1; i < (rows.length - 1); i++) {
          shouldSwitch = false;
          x = rows[i].getElementsByTagName("A")[n];
          y = rows[i + 1].getElementsByTagName("A")[n];
          if (dir == "asc") {
            if (x.innerHTML.toLowerCase() > y.innerHTML.toLowerCase()) {
              shouldSwitch = true;
              break;
            }
          } else if (dir == "desc") {
            if (x.innerHTML.toLowerCase() < y.innerHTML.toLowerCase()) {
              shouldSwitch = true;
              break;
            }
          }
        }
        if (shouldSwitch) {
          rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
          switching = true;
          switchcount ++;
        } else {
          if (switchcount == 0 && dir == "asc") {
            dir = "desc";
            switching = true;
          }
        }
      }
    }

    document.addEventListener('DOMContentLoaded', () => {
      const jumpToCat = document.getElementById('JumpToCat');
      if (jumpToCat) {
        jumpToCat.addEventListener('change', function() {
        if (this.value) {
          window.location.hash = this.value;
        }
          this.selectedIndex = 0;
        });
        jumpToCat.addEventListener('focus', function() {
          this.selectedIndex = 0;
        });
      }
    });