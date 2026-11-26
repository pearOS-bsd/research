#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_time.h>
static int n;
void cap_dump(void *msg, const char *tag, void *conn){
  int id=n++;
  const char *cn = conn? xpc_connection_get_name(conn):0;
  printf("CAP#%d %s conn=%s\n",id,tag,cn?cn:"-");
  if(xpc_get_type(msg)!=XPC_TYPE_DICTIONARY){ char*d=xpc_copy_description(msg); printf("%s\n",d); free(d); fflush(stdout); return;}
  size_t l=0; const void*p=xpc_dictionary_get_data(msg,"root",&l);
  const char *rs=xpc_dictionary_get_string(msg,"replysig");
  printf("  sequence=%llu proxynum=%llu f=%llu replysig=%s root_len=%zu\n",(unsigned long long)xpc_dictionary_get_uint64(msg,"sequence"),(unsigned long long)xpc_dictionary_get_uint64(msg,"proxynum"),(unsigned long long)xpc_dictionary_get_uint64(msg,"f"),rs?rs:"-",l);
  char nm[128]; if(p){ snprintf(nm,128,"/tmp/cap/%03d_%s.root",id,tag); FILE*f=fopen(nm,"wb"); fwrite(p,1,l,f); fclose(f);}
  xpc_object_t ool=xpc_dictionary_get_value(msg,"ool");
  if(ool&&xpc_get_type(ool)==XPC_TYPE_ARRAY){ for(size_t i=0;i<xpc_array_get_count(ool);i++){ size_t ol=0; xpc_object_t o=xpc_array_get_value(ool,i); const void*op=xpc_data_get_bytes_ptr(o); ol=xpc_data_get_length(o); printf("  ool[%zu] len=%zu\n",i,ol); snprintf(nm,128,"/tmp/cap/%03d_%s.ool%zu",id,tag,i); FILE*f=fopen(nm,"wb"); fwrite(op,1,ol,f); fclose(f);} }
  char*d=xpc_copy_description(msg); printf("%s\n",d); free(d); fflush(stdout);
}
