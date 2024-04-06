module test105;

import config;
import cppconvhelpers;

/+ #define va_start(v,l)	__builtin_va_start(v,l)
#define va_end(v)	__builtin_va_end(v)
#define va_arg(v,l)	__builtin_va_arg(v,l)
#define va_copy(d,s)	__builtin_va_copy(d,s)
#define va_list __builtin_va_list

extern "C"
{ +/
int printf ( const(char)*  format, ... );
void* malloc(uint);
uint strlen(const(char)*);
char* strcat(char* dest, const(char)* src);
int vprintf(const(char)* format, /+ va_list +/ cppconvhelpers.va_list ap);
/+ } +/

// http://www.cplusplus.com/reference/cstdarg/va_arg/
int FindMax (int n, ...)
{
  int i;int val;int largest;
  /+ va_list +/cppconvhelpers.va_list vl;
  /+ va_start(vl,n) +/va_start(vl,n);
  largest=/+ va_arg(vl,int) +/cast(int) ( va_arg!(int)(vl));
  for (i=1;i<n;i++)
  {
    val=/+ va_arg(vl,int) +/cast(int) ( va_arg!(int)(vl));
    largest=(largest>val)?largest:val;
  }
  /+ va_end(vl) +/va_end(vl);
  return largest;
}

// http://www.cplusplus.com/reference/cstdarg/va_copy/
void PrintInts (int first,...)
{
  char*  buffer;
  const(char)*  format = "[%d] ";
  int count = 0;
  int val = first;
  /+ va_list +/cppconvhelpers.va_list vl;cppconvhelpers.va_list vl_count;
  /+ va_start(vl,first) +/va_start(vl,first);

  /* count number of arguments: */
  /+ va_copy(vl_count,vl) +/va_copy(vl_count,vl);
  while (val != 0) {
    val=/+ va_arg(vl_count,int) +/cast(int) ( va_arg!(int)(vl_count));
    ++count;
  }
  /+ va_end(vl_count) +/va_end(vl_count);

  /* allocate storage for format string: */
  buffer = cast(char*) malloc (strlen(format)*count+1);
  buffer[0]='\0';

  /* generate format string: */
  for (;count>0;--count) {
    strcat (buffer,format);
  }

  /* print integers: */
  printf (format,first);
  vprintf (buffer,vl);

  /+ va_end(vl) +/va_end(vl);
}

int main ()
{
  int m;
  m= FindMax (7,702,422,631,834,892,104,772);
  printf ("The largest value is: %d\n",m);

  PrintInts (10,20,30,40,50,0);
  return 0;
}

