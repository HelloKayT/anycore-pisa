#include <stdio.h>
#include <stdlib.h>
#include "vpi_user.h"

#include "Thread.h"
#include "bp_table.h"
#include "VPI_global_vars.h"

int getBpCounter_calltf(char *user_data)
{
  unsigned int data;
  vpiHandle systf_handle, arg_iterator, arg_handle, reg_handle;
  s_vpi_value current_value;
  s_vpi_value value_s;
  //unsigned long long instruction;


  /* obtain a handle to the system task instance. */
  systf_handle  = vpi_handle(vpiSysTfCall, 0);

  /* obtain handle to system task argument. */
  arg_iterator  = vpi_iterate(vpiArgument, systf_handle);
  reg_handle    = vpi_scan(arg_iterator);

  /* free iterator memory */
  vpi_free_object(arg_iterator);

  /* read current value */
  current_value.format = vpiIntVal;  /* read value as a integer */
  vpi_get_value(reg_handle, &current_value);

  data = (unsigned int) BPTAB[0]->get_counter((unsigned int)current_value.value.integer);
  //vpi_printf("Addr:%x Data read:%x\n",(unsigned int)current_value.value.integer,data);
  //
#ifdef VPI_DEBUG  
  vpi_printf("-----------\n");
  vpi_printf("GetCounter-> Entry: %x Counter Value: %x\n",(unsigned int)current_value.value.integer,data);
#endif


  value_s.format        = vpiIntVal;
  value_s.value.integer = data;

  
  vpi_put_value(systf_handle, &value_s, 0, vpiNoDelay);

 
  return(0);    
}




// Associate C Function with a New System Function
void getBpCounter_register() {
  s_vpi_systf_data task_data_s;

  task_data_s.type      = vpiSysFunc;
  //task_data_s.sysfunctype = vpiSysFuncSized;
  task_data_s.tfname    = "$getBpCounter";
  task_data_s.calltf    = getBpCounter_calltf;
  task_data_s.compiletf = 0;
  //task_data_s.sizetf    = readInst_sizetf;

  vpi_register_systf(&task_data_s);
}
