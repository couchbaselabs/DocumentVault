from pypdf import PdfReader, PdfWriter                                                                                                                                   
import sys, os, glob                                                                                                                                                   
                                                                                                                                                                         
# Usage: script.py <pattern_or_files...> <out_dir> [chunk]                                                                                                               
# Last arg is chunk size if it's a number, second-to-last is out_dir
args = sys.argv[1:]                                                                                                                                                      
if not args:                                                                                                                                                           
    print("Usage: script.py <pattern> <out_dir> [chunk]")                                                                                                                
    sys.exit(1)                                                                                                                                                        
                                                                                                                                                                         
chunk = 20                                                                                                                                                             
if args[-1].isdigit():
    chunk = int(args.pop())                                                                                                                                              
 
out_dir = args.pop()                                                                                                                                                     
os.makedirs(out_dir, exist_ok=True)                                                                                                                                    

files = []                                                                                                                                                               
for a in args:
    files.extend(glob.glob(a) or [a])                                                                                                                                    
                                                                                                                                                                       
if not files:
    print("No files matched")
    sys.exit(1)                                                                                                                                                          
 
for src in sorted(files):                                                                                                                                                
    reader = PdfReader(src)                                                                                                                                            
    total = len(reader.pages)
    base = os.path.splitext(os.path.basename(src))[0]
    if total <= chunk:                                                                                                                                                   
        print(f"⏭  Skipping {os.path.basename(src)} ({total} pages, already small)")
        continue                                                                                                                                                         
    print(f"✂️   {os.path.basename(src)} ({total} pages)")                                                                                                              
    for i in range(0, total, chunk):                                                                                                                                     
        w = PdfWriter()
        for p in reader.pages[i:i+chunk]:                                                                                                                                
            w.add_page(p)                                                                                                                                                
        out = os.path.join(out_dir, f"{base}_part{i//chunk+1:03d}.pdf")
        with open(out, 'wb') as f:                                                                                                                                       
            w.write(f)                                                                                                                                                   
        print(f"    → {os.path.basename(out)} ({min(chunk, total-i)} pages)")
                                                                                                                                                                         
print("Done")  
