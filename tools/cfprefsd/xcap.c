// (copy of research/tools/launchservices/probes/xcap.c, plus incoming events through xpc_connection_set_event_handler)
// DYLD_INSERT_LIBRARIES interposer: logs every XPC connection creation and every message sent / reply received through
// xpc_connection_send_message[_with_reply[_sync]], with the xpc description; saves data blobs (NSXPC "root", "ool" data) to $XCAP_DIR (default /tmp/lscap).
// Build (macOS): clang -dynamiclib xcap.c -o xcap.dylib     Use: DYLD_INSERT_LIBRARIES=./xcap.dylib ./client
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <Block.h>
extern size_t xpc_shmem_map(xpc_object_t, void **region);
static int n; static const char *dir(void){ const char*d=getenv("XCAP_DIR"); return d?d:"/tmp/lscap"; }
static void dump(xpc_object_t msg,const char*tag,xpc_connection_t conn){
  int id=__sync_fetch_and_add(&n,1); const char*cn=conn?xpc_connection_get_name(conn):0;
  printf("CAP#%03d %s conn=%s\n",id,tag,cn?cn:"-");
  if(xpc_get_type(msg)==XPC_TYPE_DICTIONARY){
    size_t l=0; const void*p=xpc_dictionary_get_data(msg,"root",&l);
    const char*rs=xpc_dictionary_get_string(msg,"replysig");
    if(p){ char nm[256]; snprintf(nm,256,"%s/%03d_%s.root",dir(),id,tag); FILE*f=fopen(nm,"wb"); if(f){fwrite(p,1,l,f);fclose(f);} printf("  root_len=%zu replysig=%s seq=%llu\n",l,rs?rs:"-",(unsigned long long)xpc_dictionary_get_uint64(msg,"sequence")); }
    xpc_object_t ool=xpc_dictionary_get_value(msg,"ool");
    if(ool&&xpc_get_type(ool)==XPC_TYPE_ARRAY) for(size_t i=0;i<xpc_array_get_count(ool);i++){ xpc_object_t o=xpc_array_get_value(ool,i); char nm[256]; snprintf(nm,256,"%s/%03d_%s.ool%zu",dir(),id,tag,i);
      if(xpc_get_type(o)==XPC_TYPE_DATA){ FILE*f=fopen(nm,"wb"); if(f){fwrite(xpc_data_get_bytes_ptr(o),1,xpc_data_get_length(o),f);fclose(f);} } }
  }
  if(xpc_get_type(msg)==XPC_TYPE_DICTIONARY){ // save every shared memory value as <n>_<tag>.shm.<key>
    xpc_dictionary_apply(msg,^bool(const char*k,xpc_object_t v){ if(xpc_get_type(v)==XPC_TYPE_SHMEM){ void*r=0; size_t l=xpc_shmem_map(v,&r); if(l&&r){ char nm[256]; snprintf(nm,256,"%s/%03d_%s.shm.%s",dir(),id,tag,k); FILE*f=fopen(nm,"wb"); if(f){fwrite(r,1,l,f);fclose(f);} } } return true; }); }
  char*d=xpc_copy_description(msg); printf("%s\n",d); free(d); fflush(stdout);
}
static xpc_connection_t my_create_mach_service(const char*name,dispatch_queue_t q,uint64_t flags){ printf("CONNECT %s flags=%llu\n",name,(unsigned long long)flags); fflush(stdout); return xpc_connection_create_mach_service(name,q,flags); }
static void my_send(xpc_connection_t c,xpc_object_t m){ dump(m,"send",c); xpc_connection_send_message(c,m); }
static void my_send_reply(xpc_connection_t c,xpc_object_t m,dispatch_queue_t q,xpc_handler_t h){
  dump(m,"asend",c); xpc_handler_t hh=Block_copy(h);
  xpc_connection_send_message_with_reply(c,m,q,^(xpc_object_t r){ dump(r,"areply",c); if(hh) hh(r); });
}
static xpc_object_t my_send_sync(xpc_connection_t c,xpc_object_t m){ dump(m,"ssend",c); xpc_object_t r=xpc_connection_send_message_with_reply_sync(c,m); if(r) dump(r,"sreply",c); return r; }
#define INTERPOSE(a,b) __attribute__((used)) static struct{const void*n;const void*o;} _ip_##b __attribute__((section("__DATA,__interpose"))) = {(const void*)(unsigned long)&a,(const void*)(unsigned long)&b};
static void my_set_handler(xpc_connection_t c,xpc_handler_t h){ xpc_handler_t hh=Block_copy(h);
  xpc_connection_set_event_handler(c,^(xpc_object_t e){ dump(e,"event",c); hh(e); }); }
INTERPOSE(my_set_handler,xpc_connection_set_event_handler)
INTERPOSE(my_create_mach_service,xpc_connection_create_mach_service)
INTERPOSE(my_send,xpc_connection_send_message)
INTERPOSE(my_send_reply,xpc_connection_send_message_with_reply)
INTERPOSE(my_send_sync,xpc_connection_send_message_with_reply_sync)
__attribute__((constructor)) static void ini(void){ fprintf(stderr,"xcap loaded\n"); }
