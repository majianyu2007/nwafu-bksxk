$(function(){
	
	var self = '';
	var jsAllData = {};
	
	var viewConfig = {
			
		initialize: function(){
			self = this;
			var request = self.getRequest();
			/*获取数据*/
			queryJsInfo(request.jsh).done(function(resp) {
				var code = resp.code;
	            if (code != null && code == '1') {
	            	//处理数据
	            	self.processData(resp.data);
	            	/*初始化基本信息*/
	            	self.initJbxx(jsAllData.jbxx);
	            	/*初始化详细信息*/
	            	self.initXxxx(jsAllData.xxxx);
	            	/*初始化图表*/
	            	self.initEcharts(jsAllData.echartData);
	            	
	            }else {
	            	$.bhTip({
	                    content: '获取数据失败，请稍后重试',
	                    state: 'danger'
	                });
	            	
	            }
			});
			
			self.initFooter();
			xsxkpub.changeCopyRight();
		},
		
		/*获取路径中的参数*/
		getRequest: function() {
		    var url = location.search; //获取url中"?"符后的字串
		    var theRequest = new Object();
		    if (url.indexOf("?") != -1) {
		        var str = url.substr(1);
		        strs = str.split("&");
		        for(var i = 0; i < strs.length; i ++) {
		            theRequest[strs[i].split("=")[0]] = unescape(strs[i].split("=")[1]);
		        }
		    }
		    return theRequest;
		},
		
		/*初始化页脚信息*/
		initFooter: function(){
			queryCelebrityFamous().done(function(resp) {
                var code = resp.code;
                if (code != null && code == '1') {
                    var dataList = resp.dataList;
                    if (dataList != null && dataList.length > 0) {
                        var randomIndex = self.randomNumBoth(0, dataList.length - 1);
                        $("#ecDiv").html(dataList[randomIndex].englishContent);
                        $("#cDiv").html(dataList[randomIndex].content);
                        $("#authorDiv").html(dataList[randomIndex].author);
                    }
                }
            });
		},
		
		/*获取随机数*/
		randomNumBoth: function(Min, Max) {
	        var Range = Max - Min;
	        var Rand = Math.random();
	        //四舍五入
	        var num = Min + Math.round(Rand * Range);
	        return num;
	    },
	    
	    /*处理数据*/
	    processData: function(data){
	    	//基本信息
	    	jsAllData.jbxx = {
    			JSXM: !data.NAME?'':data.NAME,
    			JSSF: !data.JOB_TITLE?'':data.JOB_TITLE,
    			JSXB: !data.SEX?'':data.SEX,
    			XYMC: !data.COMPANY_NAME?'':data.COMPANY_NAME,
    			XSMC: !data.FACULTY_NAME?'':data.FACULTY_NAME,
    			XZZW: !data.ADMINISTRATION_TITLE?'':data.ADMINISTRATION_TITLE,
    			DSLX: !data.TUTOR_TYPE?'':data.TUTOR_TYPE,
    			GCCRCLX: !data.TYPENAME?'':data.TYPENAME,
    			GJ: !data.COUNTRY?'':data.COUNTRY
	    	};
	    	
	    	//详细信息
	    	jsAllData.xxxx = {
    			KSSJ: !data.START_DATE?'':data.START_DATE,
    			JSSJ: !data.END_DATE?'':data.END_DATE,
    			BKSSJZS: !data.DESIGN_GUIDANCE_TOTAL_CNT?'0':data.DESIGN_GUIDANCE_TOTAL_CNT,
    			ZZJCZS: !data.WORKS_TEXTBOOK_TOTAL_CNT?'0':data.WORKS_TEXTBOOK_TOTAL_CNT,
    			JYLWZS: !data.PERIODICAL_THESIS_TOTAL_CNT?'0':data.PERIODICAL_THESIS_TOTAL_CNT,
    			KYHJZS: !data.SCIENTIFIC_AWARDS_TOTAL_CNT?'0':data.SCIENTIFIC_AWARDS_TOTAL_CNT,
    			XSLWZS: !data.ACADEMIC_MASTERWORK_TOTAL_CNT?'0':data.ACADEMIC_MASTERWORK_TOTAL_CNT,
    			XSHYZS: !data.ACADEMIC_CONFERENCE_TOTAL_CNT?'0':data.ACADEMIC_CONFERENCE_TOTAL_CNT,
    			XGBGZS: !data.CONFERENCE_THESIS_TOTAL_CNT?'0':data.CONFERENCE_THESIS_TOTAL_CNT,
    			QTJZZS: !data.SERVICE_WORK_TOTAL_CNT?'0':data.SERVICE_WORK_TOTAL_CNT,
    			SHRYZS: !data.SOCIETY_HONOR_TOTAL_CNT?'0':data.SOCIETY_HONOR_TOTAL_CNT
	    	};
	    	
	    	//echart信息
	    	jsAllData.echartData = {
    			SKXS: [{
    				name: '本科生授课学时',
    				value: parseInt(!data.UNDERGRADUATE_TOTAL_TEACH_TIME?'0':data.UNDERGRADUATE_TOTAL_TEACH_TIME)
    			},{
    				name: '研究生授课学时',
    				value: parseInt(!data.GRADUATE_TOTAL_TEACH_TIME?'0':data.GRADUATE_TOTAL_TEACH_TIME)
    			}],
    			JGXM: [{
    				name: '国家级',
    				value: parseInt(!data.EDU_REFORM_PROJECT_CNT_GJJ?'0':data.EDU_REFORM_PROJECT_CNT_GJJ)
    			},{
    				name: '省部级',
    				value: parseInt(!data.EDU_REFORM_PROJECT_CNT_SBJ?'0':data.EDU_REFORM_PROJECT_CNT_SBJ)
    			}],
    			JGLW: [{
    				name: '以第一作者发表',
    				value: parseInt(!data.TEACH_THESIS_CNT_DYZZ?'0':data.TEACH_THESIS_CNT_DYZZ)
    			},{
    				name: '以通讯作者发表',
    				value: parseInt(!data.TEACH_THESIS_CNT_TXZZ?'0':data.TEACH_THESIS_CNT_TXZZ)
    			}],
    			KFKCZY: [{
    				name: '国家级',
    				value: parseInt(!data.EXCELLENT_COURSE_CNT_GJJ?'0':data.EXCELLENT_COURSE_CNT_GJJ)
    			},{
    				name: '省部级',
    				value: parseInt(!data.EXCELLENT_COURSE_CNT_SBJ?'0':data.EXCELLENT_COURSE_CNT_SBJ)
    			}],
    			JXHJ: [{
    				name: '国家级',
    				value: parseInt(!data.TEACH_AWARDS_CNT_GJJ?'0':data.TEACH_AWARDS_CNT_GJJ)
    			},{
    				name: '省部级',
    				value: parseInt(!data.TEACH_AWARDS_CNT_SBJ?'0':data.TEACH_AWARDS_CNT_SBJ)
    			}],
    			JXJS: [{
    				name: '国家级',
    				value: parseInt(!data.TEACH_COMPETE_CNT_GJJ?'0':data.TEACH_COMPETE_CNT_GJJ)
    			},{
    				name: '省部级',
    				value: parseInt(!data.TEACH_COMPETE_CNT_SBJ?'0':data.TEACH_COMPETE_CNT_SBJ)
    			}],
    			JXTT: [{
    				name: '国家级',
    				value: parseInt(!data.TEACH_TEAMS_CNT_GJJ?'0':data.TEACH_TEAMS_CNT_GJJ)
    			},{
    				name: '省部级',
    				value: parseInt(!data.TEACH_TEAMS_CNT_SBJ?'0':data.TEACH_TEAMS_CNT_SBJ)
    			}]
    			
	    	};
	    },
	    
	    /*初始化基本信息*/
	    initJbxx: function(jbxxData){
	    	var request = self.getRequest();
	    	var jbxxHtml = $("#tpl-js-jbxx").html();
	    	if(jbxxData.JSSF == '助教'){
	    		jbxxData.SFSTYLE = 'zj';
	    	}else if(jbxxData.JSSF == '讲师'){
	    		jbxxData.SFSTYLE = 'js';
	    	}else if(jbxxData.JSSF == '副教授'){
	    		jbxxData.SFSTYLE = 'fjsh';
	    	}else if(jbxxData.JSSF == '教授'){
	    		jbxxData.SFSTYLE = 'jsh';
	    	}else{
	    		jbxxData.SFSTYLE = '';
	    	}
	    	if(jbxxData.JSXB == '女'){
	    		jbxxData.XBSTYLE = 'nv';
	    	}else{
	    		jbxxData.XBSTYLE = '';
	    	}
	    	/*if(jbxxData.JSXB == '男'){
	    		jbxxData.USERIMG = '../public/images/user/male84_114.png';
	    	}else{
	    		jbxxData.USERIMG = '../public/images/user/female84_114.png';
	    	}*/
	    	jbxxData.USERIMG = BaseUrl+'/sys/xsxkapp/publicinfo/queryjzgphoto.do?jsh=' + (jbxxData.NO||'');
	    	
	    	jbxxHtml = jbxxHtml.replace(/@JSXM/g, jbxxData.JSXM)
	    			.replace(/@JSSF/g, jbxxData.JSSF)
	    			.replace(/@SFSTYLE/g, jbxxData.SFSTYLE)
					.replace(/@XBSTYLE/g, jbxxData.XBSTYLE)
					.replace(/@JSXB/g, jbxxData.JSXB)
					.replace(/@XYMC/g, jbxxData.XYMC)
					.replace(/@XSMC/g, jbxxData.XSMC)
					.replace(/@XZZW/g, jbxxData.XZZW)
					.replace(/@DSLX/g, jbxxData.DSLX)
					.replace(/@GCCRCLX/g, jbxxData.GCCRCLX)
					.replace(/@GJ/g, jbxxData.GJ)
					.replace(/@USERIMG/g, jbxxData.USERIMG);
	    			
	    	$('.jssimple .jbxx').html(jbxxHtml);
	    	
	    },
	    
	    /*初始化详细信息*/
    	initXxxx: function(xxxxData){
    		var xxxxHtml = $("#tpl-js-xxxx").html();
    		xxxxHtml = xxxxHtml.replace(/@KSSJ/g, xxxxData.KSSJ)
							.replace(/@JSSJ/g, xxxxData.JSSJ)
							.replace(/@BKSSJZS/g, xxxxData.BKSSJZS)
							.replace(/@ZZJCZS/g, xxxxData.ZZJCZS)
							.replace(/@JYLWZS/g, xxxxData.JYLWZS)
							.replace(/@KYHJZS/g, xxxxData.KYHJZS)
							.replace(/@XSLWZS/g, xxxxData.XSLWZS)
							.replace(/@XSHYZS/g, xxxxData.XSHYZS)
							.replace(/@XGBGZS/g, xxxxData.XGBGZS)
							.replace(/@QTJZZS/g, xxxxData.QTJZZS)
							.replace(/@SHRYZS/g, xxxxData.SHRYZS);
			
    		$('.jssimple .xxxx .cont').html(xxxxHtml);
    	},
    	
    	/*初始化图表*/
    	initEcharts: function(echartData){
    		/*授课学时*/
    		var skxsZs = 0;
    		var skxsDataX = [];
    		$.each(echartData.SKXS, function(skxsIndex, skxsObj){
    			skxsZs = skxsZs + skxsObj.value;
    			skxsDataX.push(skxsObj.name);
    		});
    		self.initEchartItem('skxs', skxsDataX, skxsZs, echartData.SKXS, '总学时');
    		
    		/*教改项目*/
    		var jgxmZs = 0;
    		var jgxmDataX = [];
    		$.each(echartData.JGXM, function(jgxmIndex, jgxmObj){
    			jgxmZs = jgxmZs + jgxmObj.value;
    			jgxmDataX.push(jgxmObj.name);
    		});
    		self.initEchartItem('jgxm', jgxmDataX, jgxmZs, echartData.JGXM, '项目总数');
    		
    		/*教改论文*/
    		var jglwZs = 0;
    		var jglwDataX = [];
    		$.each(echartData.JGLW, function(jglwIndex, jglwObj){
    			jglwZs = jglwZs + jglwObj.value;
    			jglwDataX.push(jglwObj.name);
    		});
    		self.initEchartItem('jglw', jglwDataX, jglwZs, echartData.JGLW, '论文总数');
    		
    		/*开放课程资源*/
    		var kfkczyZs = 0;
    		var kfkczyDataX = [];
    		$.each(echartData.KFKCZY, function(kfkczyIndex, kfkczyObj){
    			kfkczyZs = kfkczyZs + kfkczyObj.value;
    			kfkczyDataX.push(kfkczyObj.name);
    		});
    		self.initEchartItem('kfkczy', kfkczyDataX, kfkczyZs, echartData.KFKCZY, '资源总数');
    		
    		/*教学获奖*/
    		var jxhjZs = 0;
    		var jxhjDataX = [];
    		$.each(echartData.JXHJ, function(jxhjIndex, jxhjObj){
    			jxhjZs = jxhjZs + jxhjObj.value;
    			jxhjDataX.push(jxhjObj.name);
    		});
    		self.initEchartItem('jxhj', jxhjDataX, jxhjZs, echartData.JXHJ, '获奖总数');
    		
    		/*教学竞赛*/
    		var jxjsZs = 0;
    		var jxjsDataX = [];
    		$.each(echartData.JXJS, function(jxjsIndex, jxjsObj){
    			jxjsZs = jxjsZs + jxjsObj.value;
    			jxjsDataX.push(jxjsObj.name);
    		});
    		self.initEchartItem('jxjs', jxjsDataX, jxjsZs, echartData.JXJS, '竞赛总数');
    		
    		/*教学团体*/
    		var jxttZs = 0;
    		var jxttDataX = [];
    		$.each(echartData.JXTT, function(jxttIndex, jxttObj){
    			jxttZs = jxttZs + jxttObj.value;
    			jxttDataX.push(jxttObj.name);
    		});
    		self.initEchartItem('jxtt', jxttDataX, jxttZs, echartData.JXTT, '团体总数');
    	},
	    
	    /*圆环*/
	    initEchartItem: function(domId, datax, total, data, text){
	    	var option = {
    		    tooltip: {
    		        trigger: 'item',
    		        formatter: "{a} <br/>{b}: {c} ({d}%)"
    		    },
    		    legend: {
    		        orient: 'vertical',
    		        x: 'center',
    		        data: datax,
    		        bottom: '10px'
    		    },
    		    series: [
    		        {
    		            name:'',
    		            type:'pie',
    		            center: ['50%', '38%'],
    		            radius: ['55%', '65%'],
    		            avoidLabelOverlap: false,
    		            label: {
    		                normal: {
    		                    show: true,
    		                    position: 'center',
    		                    textStyle: {
    		                        fontSize: '20',
    		                        fontWeight: 'bold',
    		                        color: '#8290D2'
    		                    },
    		                    formatter: text + "\n" + total
    		                },
    		                emphasis: {
    		                    show: false,
    		                    textStyle: {
    		                        fontSize: '30',
    		                        fontWeight: 'bold'
    		                    }
    		                }
    		            },
    		            labelLine: {
    		                normal: {
    		                    show: false
    		                }
    		            },
    		            data:data
    		        }
    		    ]
    		};
	    	
	    	/*调用echart*/
	    	var myChart = echarts.init(document.getElementById(domId));
	    	myChart.setOption(option);
	    }
		
	};
	
	viewConfig.initialize();
});



