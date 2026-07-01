


function queryTeachingClassCapacity(teachingClassId, xh, capacitySuffix) {
	var timestamp = new Date().getTime();
	if(!capacitySuffix){
		capacitySuffix = '';
	}
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/teachingclass/capacity.do?teachingClassId=" + teachingClassId + "&capacitySuffix=" + capacitySuffix + "&xh=" + xh +"&timestamp=" + timestamp,
        {},
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}

