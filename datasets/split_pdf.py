from pypdf import PdfReader, PdfWriter                                                                                                                                   
import sys, os                                                                                                                                                           

src = sys.argv[1]                                                                                                                                                      
chunk = int(sys.argv[2]) if len(sys.argv) > 2 else 20

reader = PdfReader(src)
total = len(reader.pages)                                                                                                                                                
base = os.path.splitext(os.path.basename(src))[0]                                                                                                                      
out_dir = os.path.dirname(os.path.abspath(src))                                                                                                                          
   
for i in range(0, total, chunk):                                                                                                                                         
    w = PdfWriter()                                                                                                                                                    
    for p in reader.pages[i:i+chunk]:                                                                                                                                    
        w.add_page(p)
    out = os.path.join(out_dir, f"{base}_part{i//chunk+1:03d}.pdf")                                                                                                      
    with open(out, 'wb') as f:                                                                                                                                           
        w.write(f)
    print(f"  → {out} ({min(chunk, total-i)} pages)")                                                                                                                    
                                                                                                                                                                          
print(f"Done: {(total+chunk-1)//chunk} files from {total} pages")                                                                                                        
