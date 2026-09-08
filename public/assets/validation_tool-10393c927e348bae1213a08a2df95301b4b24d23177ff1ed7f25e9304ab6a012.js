// document.addEventListener('DOMContentLoaded', function() {
//     // File upload functionality
//     const fileUploadArea = document.getElementById('fileUploadArea');
//     const fileInput = document.getElementById('fileInput');
//     const browseButton = document.getElementById('browseButton');
//     const fileName = document.getElementById('fileName');
//     const uploadProgress = document.getElementById('uploadProgress');
//     const progressBar = uploadProgress ? uploadProgress.querySelector('.progress-bar') : null;
//     const validateButton = document.getElementById('validateButton');
//     const uploadForm = document.getElementById('uploadForm');
    
//     // Only initialize if we have validation results
//     if (document.getElementById('validationResults')) {
//         initializeErrorNavigation();
//     }
    
//     // File upload event handlers
//     if (browseButton) {
//         browseButton.addEventListener('click', function() {
//             fileInput.click();
//         });
//     }
    
//     if (fileInput) {
//         fileInput.addEventListener('change', function() {
//             if (this.files.length > 0) {
//                 displayFileName(this.files[0]);
//             }
//         });
//     }
    
//     if (fileUploadArea) {
//         fileUploadArea.addEventListener('dragover', function(e) {
//             e.preventDefault();
//             this.classList.add('dragover');
//         });
        
//         fileUploadArea.addEventListener('dragleave', function() {
//             this.classList.remove('dragover');
//         });
        
//         fileUploadArea.addEventListener('drop', function(e) {
//             e.preventDefault();
//             this.classList.remove('dragover');
            
//             if (e.dataTransfer.files.length > 0) {
//                 fileInput.files = e.dataTransfer.files;
//                 displayFileName(e.dataTransfer.files[0]);
//             }
//         });
        
//         fileUploadArea.addEventListener('click', function() {
//             fileInput.click();
//         });
//     }
    
//     function displayFileName(file) {
//         if (fileName) {
//             fileName.innerHTML = `<div class="alert alert-info d-flex align-items-center" role="alert">
//                 <i class="fas fa-file-excel text-success me-2"></i>
//                 <div>Selected file: <strong>${file.name}</strong></div>
//             </div>`;
//         }
//     }
    
//     // Form submission progress indicator
//     if (uploadForm) {
//         uploadForm.addEventListener('submit', function(e) {
//             // Show upload progress
//             if (uploadProgress) {
//                 uploadProgress.classList.remove('d-none');
//             }
            
//             // Simulate upload progress
//             let progress = 0;
//             const interval = setInterval(() => {
//                 progress += 5;
//                 if (progressBar) {
//                     progressBar.style.width = `${progress}%`;
//                 }
                
//                 if (progress >= 90) {
//                     clearInterval(interval);
//                 }
//             }, 100);
//         });
//     }
    
//     // Error navigation functionality
//     function initializeErrorNavigation() {
//         // Add click handlers to error cells in table
//         const errorCells = document.querySelectorAll('.error-cell');
//         errorCells.forEach(cell => {
//             cell.addEventListener('click', highlightError);
//         });
        
//         // Add click handlers to error list items
//         const errorListItems = document.querySelectorAll('.error-list-item');
//         errorListItems.forEach(item => {
//             item.addEventListener('click', function() {
//                 const rowIndex = this.dataset.row;
//                 const column = this.dataset.column;
//                 highlightErrorInTable(rowIndex, column);
//             });
//         });
//     }
    
//     // Highlight error in table when clicked from error list
//     function highlightErrorInTable(rowIndex, column) {
//         const row = document.getElementById(`row-${rowIndex}`);
//         if (row) {
//             // Remove previous highlights
//             document.querySelectorAll('.highlight-error').forEach(el => {
//                 el.classList.remove('highlight-error');
//             });
            
//             // Find the cell in the row
//             const cells = row.querySelectorAll('td');
//             const headers = getHeadersFromTable();
//             const headerIndex = headers.indexOf(column);
            
//             if (headerIndex >= 0 && cells[headerIndex]) {
//                 cells[headerIndex].classList.add('highlight-error');
//                 cells[headerIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
//             }
//         }
//     }
    
//     // Get headers from the table
//     function getHeadersFromTable() {
//         const headers = [];
//         const headerRow = document.querySelector('#dataTable thead tr');
//         if (headerRow) {
//             const headerCells = headerRow.querySelectorAll('th');
//             headerCells.forEach(cell => {
//                 headers.push(cell.textContent.trim());
//             });
//         }
//         return headers;
//     }
    
//     // Highlight error when clicked in table
//     function highlightError() {
//         const rowIndex = this.dataset.row;
//         const column = this.dataset.column;
        
//         // Remove previous highlights
//         document.querySelectorAll('.highlight-error').forEach(el => {
//             el.classList.remove('highlight-error');
//         });
        
//         // Add highlight to clicked cell
//         this.classList.add('highlight-error');
        
//         // Scroll to the error in the error list
//         const errorItems = document.querySelectorAll('.error-list-item');
//         for (let i = 0; i < errorItems.length; i++) {
//             if (errorItems[i].dataset.row === rowIndex && errorItems[i].dataset.column === column) {
//                 errorItems[i].scrollIntoView({ behavior: 'smooth', block: 'center' });
//                 break;
//             }
//         }
//     }
    
//     // Initialize tooltips
//     const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
//     const tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
//         return new bootstrap.Tooltip(tooltipTriggerEl);
//     });
// });



// File upload functionality
// document.addEventListener('DOMContentLoaded', function() {
//   const fileUploadArea = document.getElementById('fileUploadArea');
//   const fileInput = document.getElementById('fileInput');
//   const browseButton = document.getElementById('browseButton');
//   const fileName = document.getElementById('fileName');
//   const uploadProgress = document.getElementById('uploadProgress');
//   const progressBar = uploadProgress ? uploadProgress.querySelector('.progress-bar') : null;
//   const uploadForm = document.getElementById('uploadForm');

//   // Browse button click handler - FIXED
//   if (browseButton && fileInput) {
//     browseButton.addEventListener('click', function(e) {
//       e.preventDefault(); // Prevent any default behavior
//       e.stopPropagation(); // Stop event bubbling
//       fileInput.click(); // Trigger file input click
//     });
//   }

//   // File input change handler
//   if (fileInput) {
//     fileInput.addEventListener('change', function() {
//       if (this.files.length > 0) {
//         displayFileName(this.files[0]);
//       }
//     });
//   }

//   // Drag and drop functionality
//   if (fileUploadArea) {
//     // Prevent default drag behaviors
//     ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
//       fileUploadArea.addEventListener(eventName, preventDefaults, false);
//       document.body.addEventListener(eventName, preventDefaults, false);
//     });

//     // Highlight drop area when item is dragged over it
//     ['dragenter', 'dragover'].forEach(eventName => {
//       fileUploadArea.addEventListener(eventName, highlight, false);
//     });

//     ['dragleave', 'drop'].forEach(eventName => {
//       fileUploadArea.addEventListener(eventName, unhighlight, false);
//     });

//     // Handle dropped files
//     fileUploadArea.addEventListener('drop', handleDrop, false);

//     // Click on upload area to trigger file input
//     fileUploadArea.addEventListener('click', function() {
//       if (fileInput) {
//         fileInput.click();
//       }
//     });
//   }

//   function preventDefaults(e) {
//     e.preventDefault();
//     e.stopPropagation();
//   }

//   function highlight() {
//     fileUploadArea.classList.add('dragover');
//   }

//   function unhighlight() {
//     fileUploadArea.classList.remove('dragover');
//   }

//   function handleDrop(e) {
//     const dt = e.dataTransfer;
//     const files = dt.files;
    
//     if (files.length > 0) {
//       fileInput.files = files;
//       displayFileName(files[0]);
//     }
//   }

//   function displayFileName(file) {
//     if (fileName && file) {
//       fileName.innerHTML = `
//         <div class="alert alert-info d-flex align-items-center" role="alert">
//           <i class="fas fa-file-excel text-success me-2"></i>
//           <div>
//             Selected file: <strong>${file.name}</strong>
//             <br>
//             <small class="text-muted">Size: ${formatFileSize(file.size)}</small>
//           </div>
//         </div>
//       `;
//     }
//   }

//   function formatFileSize(bytes) {
//     if (bytes === 0) return '0 Bytes';
//     const k = 1024;
//     const sizes = ['Bytes', 'KB', 'MB', 'GB'];
//     const i = Math.floor(Math.log(bytes) / Math.log(k));
//     return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
//   }

//   // Form submission progress indicator
//   if (uploadForm) {
//     uploadForm.addEventListener('submit', function(e) {
//       // Validate file is selected
//       if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
//         e.preventDefault();
//         alert('Please select an Excel file to upload.');
//         return;
//       }

//       // Show upload progress
//       if (uploadProgress) {
//         uploadProgress.classList.remove('d-none');
//       }
      
//       // Simulate upload progress
//       let progress = 0;
//       const interval = setInterval(() => {
//         progress += 5;
//         if (progressBar) {
//           progressBar.style.width = `${progress}%`;
//         }
        
//         if (progress >= 90) {
//           clearInterval(interval);
//         }
//       }, 100);
//     });
//   }
// });

// app/assets/javascripts/validation_tool.js
document.addEventListener('DOMContentLoaded', function() {
    const fileUploadArea = document.getElementById('fileUploadArea');
    const fileInput = document.getElementById('fileInput');
    const browseButton = document.getElementById('browseButton');
    const fileNameDisplay = document.getElementById('fileName');
    const uploadProgress = document.getElementById('uploadProgress');
    const progressBar = uploadProgress ? uploadProgress.querySelector('.progress-bar') : null;
    const uploadForm = document.getElementById('uploadForm');
    const validationResults = document.getElementById('validationResults');
    const dataTable = document.getElementById('dataTable');

    // --- Utility Functions ---

    function preventDefaults(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    function highlightDrag() {
        fileUploadArea.classList.add('dragover');
    }

    function unhighlightDrag() {
        fileUploadArea.classList.remove('dragover');
    }

    function formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    function displayNotification(message, type = 'danger') {
        const alertHtml = `
            <div id="tempAlert" class="alert alert-${type} alert-dismissible fade show" role="alert">
                ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
            </div>
        `;
        
        // Remove existing temp alert and add new one
        const existingAlert = document.getElementById('tempAlert');
        if (existingAlert) existingAlert.remove();
        
        const alertContainer = document.querySelector('.container .row');
        if (alertContainer) {
             alertContainer.insertAdjacentHTML('afterbegin', alertHtml);
        }
    }


    function displayFileName(file) {
        if (fileNameDisplay && file) {
            fileNameDisplay.innerHTML = `
                <div class="alert alert-info d-flex align-items-center" role="alert">
                    <i class="fas fa-file-excel text-success me-2"></i>
                    <div>
                        Selected file: <strong>${file.name}</strong>
                        <br>
                        <small class="text-muted">Size: ${formatFileSize(file.size)}</small>
                    </div>
                </div>
            `;
        }
    }

    function handleDrop(e) {
        const dt = e.dataTransfer;
        const files = dt.files;
        
        if (files.length > 0) {
            fileInput.files = files;
            displayFileName(files[0]);
        }
    }

    // --- Event Handlers ---

    // File input change handler
    if (fileInput) {
        fileInput.addEventListener('change', function() {
            if (this.files.length > 0) {
                displayFileName(this.files[0]);
            }
        });
    }

    // Browse button click handler
    if (browseButton && fileInput) {
        browseButton.addEventListener('click', function(e) {
            e.preventDefault();
            fileInput.click();
        });
    }

    // Drag and drop functionality
    if (fileUploadArea) {
        ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
            fileUploadArea.addEventListener(eventName, preventDefaults, false);
            // document.body.addEventListener(eventName, preventDefaults, false); // Removed body listener to prevent conflicts
        });

        ['dragenter', 'dragover'].forEach(eventName => {
            fileUploadArea.addEventListener(eventName, highlightDrag, false);
        });

        ['dragleave', 'drop'].forEach(eventName => {
            fileUploadArea.addEventListener(eventName, unhighlightDrag, false);
        });

        fileUploadArea.addEventListener('drop', handleDrop, false);

        // Click on upload area to trigger file input (handled by HTML structure, but keeping click listener clean)
        fileUploadArea.addEventListener('click', function(e) {
            // Check if target is not the button, as the button handler is separate
            if (e.target.id !== 'browseButton' && fileInput) {
                fileInput.click();
            }
        });
    }

    // Form submission progress indicator
    if (uploadForm) {
        uploadForm.addEventListener('submit', function(e) {
            // Validate file is selected
            if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
                e.preventDefault();
                displayNotification('Please select an Excel file to upload before validating.', 'warning');
                return;
            }

            // Show upload progress
            if (uploadProgress) {
                uploadProgress.classList.remove('d-none');
            }
            
            // Simulate upload progress
            let progress = 0;
            const interval = setInterval(() => {
                progress += 5;
                if (progressBar) {
                    // Ensures progress bar doesn't go over 90% until server responds
                    progressBar.style.width = `${Math.min(progress, 90)}%`;
                }
                
                if (progress >= 100) {
                    clearInterval(interval);
                }
            }, 100);
        });
    }
    
    // --- Error Navigation ---

    function initializeErrorNavigation() {
        // Find all error links in the summary list
        const errorLinks = document.querySelectorAll('.error-list-item a');
        
        errorLinks.forEach(link => {
            link.addEventListener('click', function(e) {
                e.preventDefault();
                
                // Get the target ID from the href (e.g., #cell-1-CONVERSION PRODUCT)
                const targetId = this.getAttribute('href').substring(1); 
                const targetCell = document.getElementById(targetId);
                
                if (targetCell) {
                    // 1. Remove previous highlights
                    document.querySelectorAll('.highlight-error').forEach(el => {
                        el.classList.remove('highlight-error');
                    });
                    
                    // 2. Add highlight to the new cell
                    targetCell.classList.add('highlight-error');
                    
                    // 3. Scroll to the cell
                    targetCell.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            });
        });

        // Add handler to automatically remove highlight after a few seconds
        dataTable.addEventListener('animationend', (event) => {
            if (event.animationName === 'pulse' && event.target.classList.contains('highlight-error')) {
                setTimeout(() => {
                    event.target.classList.remove('highlight-error');
                }, 3000); // Highlight lasts for 3 seconds
            }
        });
    }

    // Initialize error navigation if results are present
    if (validationResults && dataTable) {
        initializeErrorNavigation();
    }
});
